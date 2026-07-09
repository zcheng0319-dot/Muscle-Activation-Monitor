/**
 * My_EMG M1 firmware
 *
 * Hardware:
 *   - Seeed Studio XIAO ESP32C3
 *   - Cheez.sEMG analog signal on D0
 *   - No wear-detection wire
 *
 * Signal path:
 *   500 Hz ADC -> CheezsEMG v1.0.2 official filter/envelope
 *              -> 50 Hz unnormalized envelope notifications
 *
 * BLE v2 sample:
 *   {"v":2,"type":"sample","env":36,"deviceMs":1234,"seq":12}
 *
 * BLE v2 quality (once per second):
 *   {"v":2,"type":"quality","deviceMs":1234,
 *    "rawSamples":500,"nearRailSamples":0,"clipRatio":0.000000}
 *
 * Calibration command:
 *   calibrate_rest
 *
 * The firmware intentionally does not calculate MVC percentages, activation
 * percentages, repetitions, exercise scores, or rankings.
 */

#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <CheezsEMG.h>
#include <esp_attr.h>
#include <esp_system.h>

#define EMG_PIN D0

// CheezsEMG v1.0.2 requires a detect pin. This project has no yellow
// wear-detection wire, so D1 is left physically unconnected and ignored.
#define UNUSED_DETECT_PIN D1

#define DEVICE_NAME "My_EMG"
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define EMG_CHAR_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

static const uint32_t kSampleRateHz = 500;
static const uint32_t kSampleNotificationIntervalMs = 20;
static const uint32_t kQualityNotificationIntervalMs = 1000;
static const uint32_t kPowerStabilizationDelayMs = 1000;
static const uint32_t kAdvertisingCheckIntervalMs = 2000;
static const uint32_t kRestartDelayMs = 250;
static const uint32_t kMaxDeadAdvertisingChecks = 3;
static const uint32_t kBootCounterMagic = 0x424F4F54;  // "BOOT"

static const uint32_t kPrepareDurationMs = 2000;
static const uint32_t kRestCalibrationDurationMs = 3000;
static const uint32_t kMinimumCalibrationSamples = 1400;

static const int kNearLowRail = 8;
static const int kNearHighRail = 4087;

// M0 provisional calibration limits.
static const float kMaximumRestClipRatio = 0.001f;
static const float kMaximumRestDriftFraction = 0.25f;

static const int kEnvelopeHistogramSize = 4096;
static const uint32_t kDriftWindowSamples = 500;

// Survives SW/WDT/brown-out resets but not a true power cycle, so a
// magic value distinguishes valid counts from random power-on garbage.
RTC_NOINIT_ATTR uint32_t abnormalResetCounterMagic;
RTC_NOINIT_ATTR uint32_t abnormalResetCounter;

CheezsEMG emg(EMG_PIN, UNUSED_DETECT_PIN, kSampleRateHz);

BLECharacteristic* emgCharacteristic = nullptr;
BLEAdvertising* bleAdvertising = nullptr;

volatile bool deviceConnected = false;
volatile bool everConnected = false;
volatile bool connectionStarted = false;
volatile bool disconnectHandled = true;
volatile bool restCalibrationRequested = false;

uint32_t notificationSequence = 0;
uint32_t lastSampleNotificationMs = 0;
uint32_t lastAdvertisingCheckMs = 0;
uint32_t deadAdvertisingChecks = 0;

uint32_t qualityWindowStartedMs = 0;
uint32_t qualityRawSamples = 0;
uint32_t qualityNearRailSamples = 0;

enum class CalibrationState {
  uncalibrated,
  preparing,
  collectingRest,
  complete,
  failed,
};

CalibrationState calibrationState = CalibrationState::uncalibrated;
bool calibrationValid = false;
uint32_t calibrationStageStartedMs = 0;

uint32_t calibrationSampleCount = 0;
uint32_t calibrationNearRailCount = 0;
uint32_t calibrationEnvelopeOverflow = 0;
uint32_t calibrationEnvelopeHistogram[kEnvelopeHistogramSize];

uint64_t calibrationDriftWindowSum = 0;
uint32_t calibrationDriftWindowCount = 0;
uint32_t calibrationCompletedDriftWindows = 0;
float calibrationDriftMeanMinimum = 0.0f;
float calibrationDriftMeanMaximum = 0.0f;

int sessionBaseline = 0;
int sessionNoise = 0;

void resetQualityWindow(uint32_t nowMs) {
  qualityWindowStartedMs = nowMs;
  qualityRawSamples = 0;
  qualityNearRailSamples = 0;
}

void resetCalibrationStats() {
  calibrationSampleCount = 0;
  calibrationNearRailCount = 0;
  calibrationEnvelopeOverflow = 0;

  memset(
      calibrationEnvelopeHistogram,
      0,
      sizeof(calibrationEnvelopeHistogram));

  calibrationDriftWindowSum = 0;
  calibrationDriftWindowCount = 0;
  calibrationCompletedDriftWindows = 0;
  calibrationDriftMeanMinimum = 0.0f;
  calibrationDriftMeanMaximum = 0.0f;
}

bool isNearAdcRail(int raw) {
  return raw <= kNearLowRail || raw >= kNearHighRail;
}

void notifyJson(const char* payload) {
  if (!deviceConnected || emgCharacteristic == nullptr) {
    return;
  }

  emgCharacteristic->setValue(payload);
  emgCharacteristic->notify();
}

void notifyCalibrationState(const char* state) {
  char payload[112];

  snprintf(
      payload,
      sizeof(payload),
      "{\"v\":2,\"type\":\"calibration\",\"state\":\"%s\"}",
      state);

  notifyJson(payload);
}

void notifyCalibrationFailure(const char* reason) {
  char payload[160];

  snprintf(
      payload,
      sizeof(payload),
      "{\"v\":2,\"type\":\"calibration\",\"state\":\"failed\","
      "\"reason\":\"%s\"}",
      reason);

  notifyJson(payload);
}

void notifyCalibrationComplete(int baseline, int noise) {
  char payload[176];

  snprintf(
      payload,
      sizeof(payload),
      "{\"v\":2,\"type\":\"calibration\",\"state\":\"complete\","
      "\"baseline\":%d,\"noise\":%d,\"quality\":\"good\"}",
      baseline,
      noise);

  notifyJson(payload);
}

void notifySample(int envelope, uint32_t nowMs) {
  char payload[128];

  snprintf(
      payload,
      sizeof(payload),
      "{\"v\":2,\"type\":\"sample\",\"env\":%d,"
      "\"deviceMs\":%lu,\"seq\":%lu}",
      envelope,
      static_cast<unsigned long>(nowMs),
      static_cast<unsigned long>(notificationSequence++));

  notifyJson(payload);
}

void notifyQuality(
    uint32_t nowMs,
    uint32_t rawSamples,
    uint32_t nearRailSamples) {
  if (!deviceConnected) {
    return;
  }

  const float clipRatio =
      rawSamples > 0
          ? static_cast<float>(nearRailSamples) /
                static_cast<float>(rawSamples)
          : 0.0f;

  char payload[192];

  snprintf(
      payload,
      sizeof(payload),
      "{\"v\":2,\"type\":\"quality\",\"deviceMs\":%lu,"
      "\"rawSamples\":%lu,\"nearRailSamples\":%lu,"
      "\"clipRatio\":%.6f}",
      static_cast<unsigned long>(nowMs),
      static_cast<unsigned long>(rawSamples),
      static_cast<unsigned long>(nearRailSamples),
      clipRatio);

  notifyJson(payload);
}

int calibrationHistogramMedian() {
  const uint32_t representedSamples =
      calibrationSampleCount - calibrationEnvelopeOverflow;

  if (representedSamples == 0) {
    return 0;
  }

  const uint32_t target = (representedSamples - 1) / 2;
  uint32_t cumulative = 0;

  for (int value = 0; value < kEnvelopeHistogramSize; value++) {
    cumulative += calibrationEnvelopeHistogram[value];

    if (cumulative > target) {
      return value;
    }
  }

  return kEnvelopeHistogramSize - 1;
}

int calibrationHistogramMad(int median) {
  const uint32_t representedSamples =
      calibrationSampleCount - calibrationEnvelopeOverflow;

  if (representedSamples == 0) {
    return 0;
  }

  const uint32_t target = (representedSamples - 1) / 2;
  uint32_t cumulative = calibrationEnvelopeHistogram[median];

  if (cumulative > target) {
    return 0;
  }

  for (int deviation = 1;
       deviation < kEnvelopeHistogramSize;
       deviation++) {
    const int lower = median - deviation;
    const int upper = median + deviation;

    if (lower >= 0) {
      cumulative += calibrationEnvelopeHistogram[lower];
    }

    if (upper < kEnvelopeHistogramSize) {
      cumulative += calibrationEnvelopeHistogram[upper];
    }

    if (cumulative > target) {
      return deviation;
    }
  }

  return kEnvelopeHistogramSize - 1;
}

void addCalibrationSample(int raw, int envelope) {
  calibrationSampleCount++;

  if (isNearAdcRail(raw)) {
    calibrationNearRailCount++;
  }

  if (envelope >= 0 && envelope < kEnvelopeHistogramSize) {
    calibrationEnvelopeHistogram[envelope]++;
  } else {
    calibrationEnvelopeOverflow++;
  }

  calibrationDriftWindowSum +=
      static_cast<uint64_t>(envelope >= 0 ? envelope : 0);

  calibrationDriftWindowCount++;

  if (calibrationDriftWindowCount == kDriftWindowSamples) {
    const float windowMean =
        static_cast<float>(calibrationDriftWindowSum) /
        static_cast<float>(kDriftWindowSamples);

    if (calibrationCompletedDriftWindows == 0) {
      calibrationDriftMeanMinimum = windowMean;
      calibrationDriftMeanMaximum = windowMean;
    } else {
      calibrationDriftMeanMinimum =
          min(calibrationDriftMeanMinimum, windowMean);

      calibrationDriftMeanMaximum =
          max(calibrationDriftMeanMaximum, windowMean);
    }

    calibrationCompletedDriftWindows++;
    calibrationDriftWindowSum = 0;
    calibrationDriftWindowCount = 0;
  }
}

void failCalibration(const char* reason) {
  calibrationState = CalibrationState::failed;
  calibrationValid = false;

  notifyCalibrationFailure(reason);

  Serial.print("Calibration failed: ");
  Serial.println(reason);
}

void finishRestCalibration() {
  if (calibrationSampleCount < kMinimumCalibrationSamples ||
      calibrationCompletedDriftWindows < 2) {
    failCalibration("insufficient_samples");
    return;
  }

  const float clipRatio =
      static_cast<float>(calibrationNearRailCount) /
      static_cast<float>(calibrationSampleCount);

  if (clipRatio > kMaximumRestClipRatio) {
    failCalibration("clipping_detected");
    return;
  }

  if (calibrationEnvelopeOverflow > 0) {
    failCalibration("internal_error");
    return;
  }

  const int baseline = calibrationHistogramMedian();
  const int noise = calibrationHistogramMad(baseline);

  const float driftRange =
      calibrationDriftMeanMaximum - calibrationDriftMeanMinimum;

  const float driftFraction =
      baseline > 0
          ? driftRange / static_cast<float>(baseline)
          : 1.0f;

  if (driftFraction > kMaximumRestDriftFraction) {
    failCalibration("unstable_baseline");
    return;
  }

  sessionBaseline = baseline;
  sessionNoise = noise;
  calibrationState = CalibrationState::complete;
  calibrationValid = true;

  notifyCalibrationComplete(sessionBaseline, sessionNoise);

  Serial.print("Calibration complete. Baseline=");
  Serial.print(sessionBaseline);
  Serial.print(", noise=");
  Serial.println(sessionNoise);
}

void startRestCalibration(uint32_t nowMs) {
  calibrationValid = false;
  calibrationState = CalibrationState::preparing;
  calibrationStageStartedMs = nowMs;

  resetCalibrationStats();
  notifyCalibrationState("preparing");

  Serial.println("Rest calibration preparing.");
}

void advanceCalibration(uint32_t nowMs) {
  if (calibrationState == CalibrationState::preparing &&
      nowMs - calibrationStageStartedMs >= kPrepareDurationMs) {
    calibrationState = CalibrationState::collectingRest;
    calibrationStageStartedMs = nowMs;

    resetCalibrationStats();
    notifyCalibrationState("collecting_rest");

    Serial.println("Collecting relaxed baseline.");
    return;
  }

  if (calibrationState == CalibrationState::collectingRest &&
      nowMs - calibrationStageStartedMs >=
          kRestCalibrationDurationMs) {
    finishRestCalibration();
  }
}

void handleConnectionLifecycle(uint32_t nowMs) {
  if (connectionStarted) {
    connectionStarted = false;
    disconnectHandled = false;

    notificationSequence = 0;
    lastSampleNotificationMs = nowMs;
    resetQualityWindow(nowMs);
  }

  if (!deviceConnected && !disconnectHandled) {
    disconnectHandled = true;
    calibrationValid = false;
    calibrationState = CalibrationState::uncalibrated;
    restCalibrationRequested = false;
  }
}

void updateQualityWindow(int raw, uint32_t nowMs) {
  qualityRawSamples++;

  if (isNearAdcRail(raw)) {
    qualityNearRailSamples++;
  }

  if (nowMs - qualityWindowStartedMs <
      kQualityNotificationIntervalMs) {
    return;
  }

  const uint32_t rawSamples = qualityRawSamples;
  const uint32_t nearRailSamples = qualityNearRailSamples;

  resetQualityWindow(nowMs);
  notifyQuality(nowMs, rawSamples, nearRailSamples);
}

const char* resetReasonName(esp_reset_reason_t reason) {
  switch (reason) {
    case ESP_RST_POWERON:
      return "POWERON";
    case ESP_RST_BROWNOUT:
      return "BROWNOUT";
    case ESP_RST_SW:
      return "SW";
    case ESP_RST_INT_WDT:
      return "INT_WDT";
    case ESP_RST_TASK_WDT:
      return "TASK_WDT";
    case ESP_RST_WDT:
      return "WDT";
    case ESP_RST_PANIC:
      return "PANIC";
    case ESP_RST_DEEPSLEEP:
      return "DEEPSLEEP";
    case ESP_RST_EXT:
      return "EXT";
    default:
      return "OTHER";
  }
}

void reportBootDiagnostics() {
  const esp_reset_reason_t reason = esp_reset_reason();

  Serial.print("[boot] Reset reason: ");
  Serial.print(static_cast<int>(reason));
  Serial.print(" (");
  Serial.print(resetReasonName(reason));
  Serial.println(")");

  if (abnormalResetCounterMagic != kBootCounterMagic) {
    abnormalResetCounterMagic = kBootCounterMagic;
    abnormalResetCounter = 0;
  }

  if (reason == ESP_RST_POWERON) {
    abnormalResetCounter = 0;
  } else {
    abnormalResetCounter++;
  }

  Serial.print("[boot] Consecutive abnormal resets: ");
  Serial.println(abnormalResetCounter);
}

void restartFirmware(const char* logMessage) {
  Serial.println(logMessage);
  Serial.flush();
  delay(kRestartDelayMs);
  esp_restart();
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    deviceConnected = true;
    everConnected = true;
    connectionStarted = true;

    Serial.println("BLE connected.");
  }

  void onDisconnect(BLEServer*) override {
    deviceConnected = false;
    if (bleAdvertising != nullptr) {
      bleAdvertising->start();
    }

    Serial.println("BLE disconnected.");
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const auto value = characteristic->getValue();

    String command(value.c_str());
    command.trim();
    command.toLowerCase();

    if (command == "calibrate_rest") {
      restCalibrationRequested = true;
      Serial.println("calibrate_rest received.");
    }
  }
};

void initializeBle() {
  Serial.println("[boot] Initializing BLE device.");
  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setMTU(128);

  Serial.println("[boot] Creating BLE server and service.");
  BLEServer* server = BLEDevice::createServer();

  if (server == nullptr) {
    restartFirmware(
        "[boot] BLE server creation failed; restarting.");
  }

  server->setCallbacks(new ServerCallbacks());

  BLEService* service =
      server->createService(SERVICE_UUID);

  if (service == nullptr) {
    restartFirmware(
        "[boot] BLE service creation failed; restarting.");
  }

  emgCharacteristic = service->createCharacteristic(
      EMG_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ |
          BLECharacteristic::PROPERTY_NOTIFY |
          BLECharacteristic::PROPERTY_WRITE);

  if (emgCharacteristic == nullptr) {
    restartFirmware(
        "[boot] BLE characteristic creation failed; restarting.");
  }

  emgCharacteristic->addDescriptor(new BLE2902());
  emgCharacteristic->setCallbacks(new CommandCallbacks());

  emgCharacteristic->setValue(
      "{\"v\":2,\"type\":\"status\","
      "\"calibration\":\"uncalibrated\"}");

  service->start();
  Serial.println("[boot] BLE service started.");

  bleAdvertising = BLEDevice::getAdvertising();

  if (bleAdvertising == nullptr) {
    restartFirmware(
        "[boot] BLE advertising object missing; restarting.");
  }

  bleAdvertising->addServiceUUID(SERVICE_UUID);
  bleAdvertising->setScanResponse(true);

  bleAdvertising->start();

  Serial.println("BLE advertising started.");
}

void ensureAdvertising(uint32_t nowMs) {
  if (deviceConnected || bleAdvertising == nullptr ||
      nowMs - lastAdvertisingCheckMs < kAdvertisingCheckIntervalMs) {
    return;
  }

  lastAdvertisingCheckMs = nowMs;

  if (bleAdvertising->isAdvertising()) {
    deadAdvertisingChecks = 0;
    return;
  }

  deadAdvertisingChecks++;

  Serial.print("[BLE] Advertising stopped; restarting (check ");
  Serial.print(deadAdvertisingChecks);
  Serial.println(").");

  // Only self-reset while the device has never been connected since
  // boot: a stack that is dead on arrival needs a full restart, but a
  // board in active use must not reboot on a transient glitch.
  if (!everConnected &&
      deadAdvertisingChecks >= kMaxDeadAdvertisingChecks) {
    restartFirmware(
        "[watchdog] BLE never connected and advertising dead; "
        "restarting.");
  }

  bleAdvertising->start();
}

void setup() {
  Serial.begin(115200);
  delay(kPowerStabilizationDelayMs);
  Serial.println("[boot] Power stabilization delay complete.");

  reportBootDiagnostics();

  initializeBle();

  Serial.println("[boot] Initializing ADC and CheezsEMG.");

  analogReadResolution(12);
  analogSetPinAttenuation(EMG_PIN, ADC_11db);

  emg.begin();
  Serial.println("[boot] CheezsEMG initialized.");

  const uint32_t nowMs = millis();

  lastSampleNotificationMs = nowMs;
  lastAdvertisingCheckMs = nowMs;
  resetQualityWindow(nowMs);

  Serial.println(
      "My_EMG M1 ready. Waiting for calibrate_rest.");
}

void loop() {
  const uint32_t nowMs = millis();

  handleConnectionLifecycle(nowMs);
  ensureAdvertising(nowMs);

  if (restCalibrationRequested) {
    restCalibrationRequested = false;
    startRestCalibration(nowMs);
  }

  advanceCalibration(nowMs);

  if (CheezsEMG::checkSampleInterval()) {
    emg.processSignal();

    const int raw = emg.getRawSignal();
    const int envelope = emg.getEnvelopeSignal();
    const uint32_t sampledMs = millis();

    updateQualityWindow(raw, sampledMs);

    if (calibrationState ==
        CalibrationState::collectingRest) {
      addCalibrationSample(raw, envelope);
    }
  }

  const uint32_t outputMs = millis();

  if (outputMs - lastSampleNotificationMs >=
      kSampleNotificationIntervalMs) {
    lastSampleNotificationMs = outputMs;

    notifySample(
        emg.getEnvelopeSignal(),
        outputMs);
  }
}
