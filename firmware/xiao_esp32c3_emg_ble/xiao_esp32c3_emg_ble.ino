/**
 * XIAO ESP32C3 + Cheez.sEMG
 *
 * Signal chain:
 * raw -> DC removal -> rectification -> envelope low-pass
 *     -> session baseline/MVC -> 0-100 Act%
 *
 * BLE payload: JSON with act, raw, env, and invalid fields.
 */

#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#define EMG_PIN D0
#define DEVICE_NAME "My_EMG"

#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define EMG_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Sampling and calibration timing.
static const uint32_t kSampleIntervalMs = 10;       // 100 Hz
static const uint32_t kOutputIntervalMs = 50;       // 20 Hz
static const uint32_t kWarmupDurationMs = 2000;
static const uint32_t kRelaxCalibrationMs = 3000;
static const uint32_t kMvcCalibrationMs = 5000;
static const uint32_t kMvcWindowMs = 1000;

// Reject samples close to the 12-bit ADC rails.
static const int kRawValidMin = 8;
static const int kRawValidMax = 4087;

// Filter and output shaping.
static const float kDcAlpha = 0.001f;
static const float kEnvelopeAlpha = 0.12f;
static const float kOutputAlpha = 0.30f;
static const float kMaxStepPercent = 8.0f;
static const float kActivationDeadbandPercent = 5.0f;
static const float kMinimumMvcRange = 1.0f;

// The time-based MVC window allows short invalid-sample gaps.
static const int kMvcWindowCapacity = 160;
static const int kMinimumMvcWindowSamples = 80;
float mvcWindowValues[kMvcWindowCapacity];
uint32_t mvcWindowTimes[kMvcWindowCapacity];
int mvcWindowHead = 0;
int mvcWindowCount = 0;
float mvcWindowSum = 0.0f;

float dcLevel = 0.0f;
float envelope = 0.0f;
float baselineEnvelope = 0.0f;
float sessionMVC = 1.0f;
float actPercent = 0.0f;
bool dcInitialized = false;
bool deviceConnected = false;
volatile bool calibrationRequested = false;

int latestRaw = 0;
bool latestInvalid = false;
uint32_t lastOutputMs = 0;
uint32_t nextSampleMs = 0;

BLEServer* pServer = nullptr;
BLECharacteristic* pEmgCharacteristic = nullptr;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    deviceConnected = true;
    Serial.println("Device Connected");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    Serial.println("Device Disconnected");
    BLEDevice::startAdvertising();
  }
};

class EmgWriteCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const auto value = characteristic->getValue();
    String command(value.c_str());
    command.trim();
    command.toLowerCase();

    if (command == "r" || command == "calibrate" ||
        command == "recalibrate") {
      calibrationRequested = true;
      Serial.println("BLE recalibration command received.");
    }
  }
};

bool isRawValid(int raw) {
  return raw > kRawValidMin && raw < kRawValidMax;
}

bool updateSignalChain(int raw) {
  latestRaw = raw;
  latestInvalid = !isRawValid(raw);
  if (latestInvalid) {
    return false;
  }

  if (!dcInitialized) {
    dcLevel = static_cast<float>(raw);
    envelope = 0.0f;
    dcInitialized = true;
    return true;
  }

  dcLevel += kDcAlpha * (static_cast<float>(raw) - dcLevel);
  const float rectified = fabsf(static_cast<float>(raw) - dcLevel);
  envelope += kEnvelopeAlpha * (rectified - envelope);
  return true;
}

void printPlotterSample() {
  Serial.print("Act:");
  Serial.print(actPercent, 1);
  Serial.print(",Invalid:");
  Serial.print(latestInvalid ? 1 : 0);
  Serial.print(",Raw:");
  Serial.print(latestRaw);
  Serial.print(",Env:");
  Serial.println(envelope, 2);
}

void sampleForDuration(uint32_t durationMs, bool includeInBaseline,
                       float& envelopeSum, uint32_t& validCount) {
  const uint32_t startMs = millis();
  uint32_t nextSampleMs = startMs;
  uint32_t nextOutputMs = startMs;

  while (millis() - startMs < durationMs) {
    const uint32_t now = millis();
    if (static_cast<int32_t>(now - nextSampleMs) >= 0) {
      nextSampleMs += kSampleIntervalMs;
      if (updateSignalChain(analogRead(EMG_PIN)) && includeInBaseline) {
        envelopeSum += envelope;
        validCount++;
      }
    }

    if (static_cast<int32_t>(now - nextOutputMs) >= 0) {
      nextOutputMs += kOutputIntervalMs;
      printPlotterSample();
    }

    delay(1);
  }
}

void resetMvcWindow() {
  mvcWindowHead = 0;
  mvcWindowCount = 0;
  mvcWindowSum = 0.0f;
}

void removeOldMvcSamples(uint32_t now) {
  while (mvcWindowCount > 0 &&
         now - mvcWindowTimes[mvcWindowHead] > kMvcWindowMs) {
    mvcWindowSum -= mvcWindowValues[mvcWindowHead];
    mvcWindowHead = (mvcWindowHead + 1) % kMvcWindowCapacity;
    mvcWindowCount--;
  }
}

void addMvcWindowSample(float value, uint32_t now) {
  removeOldMvcSamples(now);

  if (mvcWindowCount == kMvcWindowCapacity) {
    mvcWindowSum -= mvcWindowValues[mvcWindowHead];
    mvcWindowHead = (mvcWindowHead + 1) % kMvcWindowCapacity;
    mvcWindowCount--;
  }

  const int tail = (mvcWindowHead + mvcWindowCount) % kMvcWindowCapacity;
  mvcWindowValues[tail] = value;
  mvcWindowTimes[tail] = now;
  mvcWindowSum += value;
  mvcWindowCount++;
}

void warmUpSignal() {
  Serial.println("Warmup: keep the sensor still.");
  float unusedSum = 0.0f;
  uint32_t unusedCount = 0;
  sampleForDuration(kWarmupDurationMs, false, unusedSum, unusedCount);
}

void calibrateRelax() {
  Serial.println("Relax calibration: keep the muscle relaxed for 3 seconds.");
  float envelopeSum = 0.0f;
  uint32_t validCount = 0;
  sampleForDuration(
      kRelaxCalibrationMs, true, envelopeSum, validCount);

  baselineEnvelope =
      validCount > 0 ? envelopeSum / static_cast<float>(validCount) : envelope;
  Serial.print("Baseline envelope: ");
  Serial.println(baselineEnvelope, 2);
}

void calibrateMvc() {
  Serial.println("MVC calibration: contract maximally for 5 seconds.");
  resetMvcWindow();
  sessionMVC = baselineEnvelope;

  const uint32_t startMs = millis();
  uint32_t nextSampleMs = startMs;
  uint32_t nextOutputMs = startMs;

  while (millis() - startMs < kMvcCalibrationMs) {
    const uint32_t now = millis();
    if (static_cast<int32_t>(now - nextSampleMs) >= 0) {
      nextSampleMs += kSampleIntervalMs;
      if (updateSignalChain(analogRead(EMG_PIN))) {
        addMvcWindowSample(envelope, now);
        const bool windowReady =
            now - startMs >= kMvcWindowMs &&
            mvcWindowCount >= kMinimumMvcWindowSamples;
        if (windowReady) {
          const float windowMean =
              mvcWindowSum / static_cast<float>(mvcWindowCount);
          if (windowMean > sessionMVC) {
            sessionMVC = windowMean;
          }
        }
      }
    }

    if (static_cast<int32_t>(now - nextOutputMs) >= 0) {
      nextOutputMs += kOutputIntervalMs;
      printPlotterSample();
    }

    delay(1);
  }

  if (sessionMVC - baselineEnvelope < kMinimumMvcRange) {
    sessionMVC = baselineEnvelope + kMinimumMvcRange;
    Serial.println("Warning: MVC range was too small; using safe minimum.");
  }

  Serial.print("Session MVC: ");
  Serial.println(sessionMVC, 2);
}

void runSessionCalibration(bool includeWarmup) {
  actPercent = 0.0f;
  if (includeWarmup) {
    warmUpSignal();
  }
  calibrateRelax();
  calibrateMvc();
  lastOutputMs = millis();
  Serial.println("Calibration complete. Send r or R to recalibrate.");
}

float calculateTargetActivation() {
  const float range = sessionMVC - baselineEnvelope;
  if (range <= 0.0f) {
    return 0.0f;
  }

  float target =
      ((envelope - baselineEnvelope) / range) * 100.0f;
  target = constrain(target, 0.0f, 100.0f);
  return target < kActivationDeadbandPercent ? 0.0f : target;
}

void updateActivationOutput() {
  const float target = calculateTargetActivation();
  float nextValue = actPercent + kOutputAlpha * (target - actPercent);
  const float delta =
      constrain(nextValue - actPercent, -kMaxStepPercent, kMaxStepPercent);
  actPercent = constrain(actPercent + delta, 0.0f, 100.0f);
  if (target == 0.0f && actPercent < 0.5f) {
    actPercent = 0.0f;
  }
}

void notifyActivation() {
  if (!deviceConnected) {
    return;
  }

  const String payload =
      "{\"act\":" + String(actPercent, 1) +
      ",\"raw\":" + String(latestRaw) +
      ",\"env\":" + String(envelope, 1) +
      ",\"invalid\":" + String(latestInvalid ? 1 : 0) +
      "}";
  pEmgCharacteristic->setValue(payload.c_str());
  pEmgCharacteristic->notify();
}

void resetCalibration() {
  actPercent = 0.0f;
  notifyActivation();
  runSessionCalibration(true);
  nextSampleMs = millis();
}

void initializeBle() {
  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pEmgCharacteristic = pService->createCharacteristic(
      EMG_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY |
          BLECharacteristic::PROPERTY_WRITE);
  pEmgCharacteristic->addDescriptor(new BLE2902());
  pEmgCharacteristic->setCallbacks(new EmgWriteCallbacks());

  pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("BLE Advertising started! Device: " + String(DEVICE_NAME));
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);

  runSessionCalibration(true);
  initializeBle();
  nextSampleMs = millis();
}

void loop() {
  if (Serial.available() > 0) {
    const char command = Serial.read();
    if (command == 'r' || command == 'R') {
      calibrationRequested = true;
    }
  }

  if (calibrationRequested) {
    calibrationRequested = false;
    resetCalibration();
  }

  const uint32_t now = millis();
  if (static_cast<int32_t>(now - nextSampleMs) >= 0) {
    nextSampleMs += kSampleIntervalMs;
    updateSignalChain(analogRead(EMG_PIN));
  }

  if (now - lastOutputMs >= kOutputIntervalMs) {
    lastOutputMs = now;
    updateActivationOutput();
    notifyActivation();
    printPlotterSample();
  }

  delay(1);
}
