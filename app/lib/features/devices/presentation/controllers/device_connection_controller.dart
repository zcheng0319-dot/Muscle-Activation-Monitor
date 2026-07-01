import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

final deviceConnectionControllerProvider =
    NotifierProvider<DeviceConnectionController, DeviceConnectionState>(
      DeviceConnectionController.new,
    );

enum DeviceSide { left, right }

class DeviceConnectionState {
  const DeviceConnectionState({
    required this.leftDevice,
    required this.rightDevice,
    this.hasScanned = false,
    this.bleSupported = true,
    this.adapterState = BluetoothAdapterState.unknown,
    this.isScanning = false,
    this.scanError,
    this.discoveredDevices = const [],
    this.leftBoundDevice,
    this.rightBoundDevice,
  });

  final EmgDeviceConnection leftDevice;
  final EmgDeviceConnection rightDevice;
  final bool hasScanned;
  final bool bleSupported;
  final BluetoothAdapterState adapterState;
  final bool isScanning;
  final String? scanError;
  final List<DiscoveredBleDevice> discoveredDevices;
  final BoundBleDevice? leftBoundDevice;
  final BoundBleDevice? rightBoundDevice;

  bool get canScan {
    return bleSupported && adapterState == BluetoothAdapterState.on;
  }

  DeviceConnectionState copyWith({
    EmgDeviceConnection? leftDevice,
    EmgDeviceConnection? rightDevice,
    bool? hasScanned,
    bool? bleSupported,
    BluetoothAdapterState? adapterState,
    bool? isScanning,
    String? scanError,
    bool clearScanError = false,
    List<DiscoveredBleDevice>? discoveredDevices,
    BoundBleDevice? leftBoundDevice,
    BoundBleDevice? rightBoundDevice,
  }) {
    return DeviceConnectionState(
      leftDevice: leftDevice ?? this.leftDevice,
      rightDevice: rightDevice ?? this.rightDevice,
      hasScanned: hasScanned ?? this.hasScanned,
      bleSupported: bleSupported ?? this.bleSupported,
      adapterState: adapterState ?? this.adapterState,
      isScanning: isScanning ?? this.isScanning,
      scanError: clearScanError ? null : scanError ?? this.scanError,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      leftBoundDevice: leftBoundDevice ?? this.leftBoundDevice,
      rightBoundDevice: rightBoundDevice ?? this.rightBoundDevice,
    );
  }
}

class DeviceConnectAttempt {
  const DeviceConnectAttempt._({
    required this.connected,
    required this.needsSelection,
  });

  const DeviceConnectAttempt.connected()
    : this._(connected: true, needsSelection: false);

  const DeviceConnectAttempt.needsSelection()
    : this._(connected: false, needsSelection: true);

  const DeviceConnectAttempt.failed()
    : this._(connected: false, needsSelection: false);

  final bool connected;
  final bool needsSelection;
}

class BoundBleDevice {
  const BoundBleDevice({required this.id, required this.name});

  final String id;
  final String name;
}

class DiscoveredBleDevice {
  const DiscoveredBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

class EmgDeviceConnection {
  static const _adcFullScale = 4095.0;

  const EmgDeviceConnection({
    required this.side,
    required this.displayName,
    this.connected = false,
    this.signalStrength = 0,
    this.rawEmg = 0,
    this.smoothEmg = 0,
    this.isInvalidSample = false,
  });

  final DeviceSide side;
  final String displayName;
  final bool connected;
  final int signalStrength;
  final double rawEmg;
  final double smoothEmg;
  final bool isInvalidSample;

  int get activationPercent {
    if (!smoothEmg.isFinite || smoothEmg <= 0) return 0;
    if (smoothEmg <= 100) return smoothEmg.round().clamp(0, 100).toInt();

    return ((smoothEmg / _adcFullScale) * 100).round().clamp(0, 100).toInt();
  }

  String get sideLabel {
    return side == DeviceSide.left ? 'Left Device' : 'Right Device';
  }

  String get statusLabel => connected ? 'Connected' : 'Not Connected';

  String get signalLabel => connected ? '$signalStrength%' : '--';

  EmgDeviceConnection copyWith({
    String? displayName,
    bool? connected,
    int? signalStrength,
    double? rawEmg,
    double? smoothEmg,
    bool? isInvalidSample,
  }) {
    return EmgDeviceConnection(
      side: side,
      displayName: displayName ?? this.displayName,
      connected: connected ?? this.connected,
      signalStrength: signalStrength ?? this.signalStrength,
      rawEmg: rawEmg ?? this.rawEmg,
      smoothEmg: smoothEmg ?? this.smoothEmg,
      isInvalidSample: isInvalidSample ?? this.isInvalidSample,
    );
  }
}

class _EmgPayload {
  const _EmgPayload({
    required this.rawEmg,
    required this.smoothEmg,
    this.invalid = false,
  });

  final double rawEmg;
  final double smoothEmg;
  final bool invalid;
}

class DeviceConnectionController extends Notifier<DeviceConnectionState> {
  static final _emgServiceUuid = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final _emgCharacteristicUuid = Guid(
    'beb5483e-36e1-4688-b7f5-ea07361b26a8',
  );

  static const _leftDeviceIdKey = 'devices.left.remote_id';
  static const _leftDeviceNameKey = 'devices.left.name';
  static const _rightDeviceIdKey = 'devices.right.remote_id';
  static const _rightDeviceNameKey = 'devices.right.name';

  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  final _emgSubscriptions = <DeviceSide, StreamSubscription<List<int>>>{};
  final _emgCharacteristics = <DeviceSide, BluetoothCharacteristic>{};
  final _connectionStateSubscriptions =
      <DeviceSide, StreamSubscription<BluetoothConnectionState>>{};
  final _connectedDevices = <DeviceSide, BluetoothDevice>{};
  bool _bleInitialized = false;

  @override
  DeviceConnectionState build() {
    ref.onDispose(() {
      _adapterStateSubscription?.cancel();
      _isScanningSubscription?.cancel();
      _scanResultsSubscription?.cancel();
      for (final subscription in _emgSubscriptions.values) {
        subscription.cancel();
      }
      for (final subscription in _connectionStateSubscriptions.values) {
        subscription.cancel();
      }
      if (_bleInitialized) {
        unawaited(_stopScanQuietly());
      }
    });

    unawaited(_loadBoundDevices());

    return const DeviceConnectionState(
      leftDevice: EmgDeviceConnection(
        side: DeviceSide.left,
        displayName: 'My_EMG',
      ),
      rightDevice: EmgDeviceConnection(
        side: DeviceSide.right,
        displayName: 'EMG-R 01',
      ),
    );
  }

  Future<void> initializeBle() async {
    if (_bleInitialized) return;
    _bleInitialized = true;

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      state = state.copyWith(bleSupported: isSupported);
      if (!isSupported) {
        state = state.copyWith(scanError: 'Bluetooth LE is not supported.');
        return;
      }

      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((
        adapterState,
      ) {
        state = state.copyWith(adapterState: adapterState);
      });
      _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
        state = state.copyWith(isScanning: isScanning);
      });
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
        state = state.copyWith(discoveredDevices: _mapScanResults(results));
      });
    } on Object catch (error) {
      state = state.copyWith(scanError: 'BLE initialization failed: $error');
    }
  }

  Future<void> scanDevices() async {
    await initializeBle();

    state = state.copyWith(hasScanned: true, clearScanError: true);

    if (!state.bleSupported) return;
    final hasPermissions = await _ensureBlePermissions();
    if (!hasPermissions) {
      state = state.copyWith(
        scanError:
            'Bluetooth permission denied. Enable Nearby devices in Settings.',
      );
      return;
    }

    if (state.adapterState != BluetoothAdapterState.on) {
      state = state.copyWith(
        scanError: 'Turn on Bluetooth and grant nearby device permissions.',
      );
      return;
    }

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } on Object catch (error) {
      state = state.copyWith(scanError: 'BLE scan failed: $error');
    }
  }

  Future<DeviceConnectAttempt> connectPreferredDevice(DeviceSide side) async {
    final currentDevice = _deviceForSide(side);
    if (currentDevice.connected) {
      return const DeviceConnectAttempt.connected();
    }

    final boundDevice = _boundDeviceForSide(side);
    if (boundDevice == null) {
      await scanDevices();
      return const DeviceConnectAttempt.needsSelection();
    }

    final ready = await _prepareBleConnection();
    if (!ready) return const DeviceConnectAttempt.failed();

    try {
      await _connectRemoteDevice(
        side: side,
        remoteId: boundDevice.id,
        name: boundDevice.name,
      );
      return const DeviceConnectAttempt.connected();
    } on Object {
      state = state.copyWith(
        scanError:
            'Could not reconnect ${boundDevice.name}. Select a device manually.',
      );
      await scanDevices();
      return const DeviceConnectAttempt.needsSelection();
    }
  }

  Future<bool> connectDiscoveredDevice(
    DeviceSide side,
    DiscoveredBleDevice discoveredDevice,
  ) async {
    final ready = await _prepareBleConnection();
    if (!ready) return false;

    try {
      await _connectRemoteDevice(
        side: side,
        remoteId: discoveredDevice.id,
        name: discoveredDevice.name,
        rssi: discoveredDevice.rssi,
      );
      return true;
    } on Object catch (error) {
      state = state.copyWith(
        scanError: 'Could not connect ${discoveredDevice.name}: $error',
      );
      return false;
    }
  }

  Future<bool> _ensureBlePermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final statuses = await permissions.request();
    final bluetoothScanStatus = statuses[Permission.bluetoothScan];
    final bluetoothConnectStatus = statuses[Permission.bluetoothConnect];
    final locationStatus = statuses[Permission.locationWhenInUse];

    final bluetoothGranted =
        (bluetoothScanStatus?.isGranted ?? true) &&
        (bluetoothConnectStatus?.isGranted ?? true);
    final locationPermanentlyDenied =
        locationStatus?.isPermanentlyDenied ?? false;

    if (locationPermanentlyDenied) {
      state = state.copyWith(
        scanError:
            'Location permission is blocked. Older Android versions need it for BLE scan.',
      );
    }

    return bluetoothGranted;
  }

  Future<bool> _prepareBleConnection() async {
    await initializeBle();
    if (!state.bleSupported) return false;

    final hasPermissions = await _ensureBlePermissions();
    if (!hasPermissions) {
      state = state.copyWith(
        scanError:
            'Bluetooth permission denied. Enable Nearby devices in Settings.',
      );
      return false;
    }

    if (state.adapterState != BluetoothAdapterState.on) {
      state = state.copyWith(scanError: 'Turn on Bluetooth to connect.');
      return false;
    }

    return true;
  }

  Future<void> _connectRemoteDevice({
    required DeviceSide side,
    required String remoteId,
    required String name,
    int? rssi,
  }) async {
    await _stopScanQuietly();

    final bluetoothDevice = BluetoothDevice.fromId(remoteId);
    await bluetoothDevice.connect(
      timeout: const Duration(seconds: 12),
      autoConnect: false,
    );
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await bluetoothDevice.requestMtu(128);
      } on Object {
        // Some Android devices negotiate MTU automatically or reject requests.
      }
    }
    await _subscribeToEmgCharacteristic(side, bluetoothDevice);
    await _listenToConnectionState(side, bluetoothDevice);
    _connectedDevices[side] = bluetoothDevice;
    await _saveBoundDevice(side, BoundBleDevice(id: remoteId, name: name));

    final signalStrength = _signalPercentFromRssi(rssi);
    if (side == DeviceSide.left) {
      state = state.copyWith(
        hasScanned: true,
        leftDevice: state.leftDevice.copyWith(
          displayName: name,
          connected: true,
          signalStrength: signalStrength,
          rawEmg: 0,
          smoothEmg: 0,
          isInvalidSample: false,
        ),
        leftBoundDevice: BoundBleDevice(id: remoteId, name: name),
        clearScanError: true,
      );
      return;
    }

    state = state.copyWith(
      hasScanned: true,
      rightDevice: state.rightDevice.copyWith(
        displayName: name,
        connected: true,
        signalStrength: signalStrength,
        rawEmg: 0,
        smoothEmg: 0,
        isInvalidSample: false,
      ),
      rightBoundDevice: BoundBleDevice(id: remoteId, name: name),
      clearScanError: true,
    );
  }

  Future<void> disconnect(DeviceSide side) async {
    await _connectionStateSubscriptions.remove(side)?.cancel();
    await _emgSubscriptions.remove(side)?.cancel();
    final characteristic = _emgCharacteristics.remove(side);
    if (characteristic != null) {
      try {
        await characteristic.setNotifyValue(false);
      } on Object {
        // The device may already be disconnected.
      }
    }

    final bluetoothDevice = _connectedDevices.remove(side);
    if (bluetoothDevice != null) {
      try {
        await bluetoothDevice.disconnect();
      } on Object {
        // The UI should still reflect the local disconnect request.
      }
    }

    if (side == DeviceSide.left) {
      state = state.copyWith(
        leftDevice: state.leftDevice.copyWith(
          connected: false,
          signalStrength: 0,
          rawEmg: 0,
          smoothEmg: 0,
          isInvalidSample: false,
        ),
      );
      return;
    }

    state = state.copyWith(
      rightDevice: state.rightDevice.copyWith(
        connected: false,
        signalStrength: 0,
        rawEmg: 0,
        smoothEmg: 0,
        isInvalidSample: false,
      ),
    );
  }

  Future<bool> sendRecalibrateCommand() async {
    debugPrint(
      'Recalibrate connected device status: '
      '${state.leftDevice.connected}',
    );
    if (!state.leftDevice.connected) {
      debugPrint('Recalibrate characteristic is null: device not connected');
      return false;
    }

    final characteristic = _emgCharacteristics[DeviceSide.left];
    debugPrint(
      'Recalibrate characteristic is '
      '${characteristic == null ? 'null' : 'not null'}',
    );
    if (characteristic == null) return false;

    final properties = characteristic.properties;
    debugPrint('Recalibrate characteristic UUID: ${characteristic.uuid}');
    debugPrint('Recalibrate characteristic properties: $properties');
    debugPrint('Recalibrate supports write: ${properties.write}');
    debugPrint(
      'Recalibrate supports writeWithoutResponse: '
      '${properties.writeWithoutResponse}',
    );
    if (!properties.write) {
      debugPrint(
        'Recalibrate write failed with error: '
        'characteristic does not support write with response',
      );
      return false;
    }

    try {
      debugPrint('Recalibrate write started');
      await characteristic
          .write(utf8.encode('r'), withoutResponse: false)
          .timeout(const Duration(seconds: 5));
      debugPrint('Recalibrate write success');
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Recalibrate write failed with error: $error');
      debugPrintStack(stackTrace: stackTrace);
      state = state.copyWith(
        scanError: 'Could not send recalibration command: $error',
      );
      return false;
    }
  }

  Future<void> _listenToConnectionState(
    DeviceSide side,
    BluetoothDevice bluetoothDevice,
  ) async {
    await _connectionStateSubscriptions.remove(side)?.cancel();
    _connectionStateSubscriptions[side] = bluetoothDevice.connectionState
        .listen((connectionState) {
          if (connectionState == BluetoothConnectionState.disconnected) {
            unawaited(_handleRemoteDisconnect(side));
          }
        });
  }

  Future<void> _handleRemoteDisconnect(DeviceSide side) async {
    await _connectionStateSubscriptions.remove(side)?.cancel();
    await _emgSubscriptions.remove(side)?.cancel();
    _emgCharacteristics.remove(side);
    _connectedDevices.remove(side);

    if (side == DeviceSide.left) {
      state = state.copyWith(
        leftDevice: state.leftDevice.copyWith(
          connected: false,
          signalStrength: 0,
          rawEmg: 0,
          smoothEmg: 0,
          isInvalidSample: false,
        ),
      );
      return;
    }

    state = state.copyWith(
      rightDevice: state.rightDevice.copyWith(
        connected: false,
        signalStrength: 0,
        rawEmg: 0,
        smoothEmg: 0,
        isInvalidSample: false,
      ),
    );
  }

  Future<void> _subscribeToEmgCharacteristic(
    DeviceSide side,
    BluetoothDevice bluetoothDevice,
  ) async {
    final services = await bluetoothDevice.discoverServices();
    final emgService = _findEmgService(services);
    if (emgService == null) {
      throw StateError('EMG service $_emgServiceUuid not found.');
    }

    final emgCharacteristic = _findEmgCharacteristic(emgService);
    if (emgCharacteristic == null) {
      throw StateError('EMG characteristic $_emgCharacteristicUuid not found.');
    }

    await _emgSubscriptions.remove(side)?.cancel();
    _emgCharacteristics[side] = emgCharacteristic;
    _emgSubscriptions[side] = emgCharacteristic.onValueReceived.listen(
      (value) => _handleEmgValue(side, value),
    );
    await emgCharacteristic.setNotifyValue(true);
  }

  BluetoothService? _findEmgService(List<BluetoothService> services) {
    for (final service in services) {
      if (_isEmgService(service)) return service;
    }
    return null;
  }

  BluetoothCharacteristic? _findEmgCharacteristic(BluetoothService service) {
    for (final characteristic in service.characteristics) {
      if (_isEmgCharacteristic(characteristic)) return characteristic;
    }
    return null;
  }

  bool _isEmgService(BluetoothService service) {
    return service.uuid.toString().toLowerCase() ==
        _emgServiceUuid.toString().toLowerCase();
  }

  bool _isEmgCharacteristic(BluetoothCharacteristic characteristic) {
    return characteristic.uuid.toString().toLowerCase() ==
        _emgCharacteristicUuid.toString().toLowerCase();
  }

  void _handleEmgValue(DeviceSide side, List<int> value) {
    final payload = _parseEmgPayload(value);
    if (payload == null) return;
    if (!payload.rawEmg.isFinite || !payload.smoothEmg.isFinite) return;

    if (side == DeviceSide.left) {
      if (payload.invalid) {
        state = state.copyWith(
          leftDevice: state.leftDevice.copyWith(isInvalidSample: true),
        );
        return;
      }
      final nextDevice = state.leftDevice.copyWith(
        rawEmg: payload.rawEmg,
        smoothEmg: payload.smoothEmg,
        isInvalidSample: false,
      );
      state = state.copyWith(leftDevice: nextDevice);
      return;
    }

    if (payload.invalid) {
      state = state.copyWith(
        rightDevice: state.rightDevice.copyWith(isInvalidSample: true),
      );
      return;
    }
    final nextDevice = state.rightDevice.copyWith(
      rawEmg: payload.rawEmg,
      smoothEmg: payload.smoothEmg,
      isInvalidSample: false,
    );
    state = state.copyWith(rightDevice: nextDevice);
  }

  _EmgPayload? _parseEmgPayload(List<int> value) {
    if (value.isEmpty) return null;

    final textValue = utf8.decode(value, allowMalformed: true).trim();
    if (_looksLikeTextPayload(textValue)) {
      return _parseEmgTextPayload(textValue);
    }

    final binaryValue = _parseBinaryEmgValue(value);
    return _EmgPayload(rawEmg: binaryValue, smoothEmg: binaryValue);
  }

  double _parseBinaryEmgValue(List<int> value) {
    final bytes = Uint8List.fromList(value);
    final byteData = ByteData.sublistView(bytes);
    if (bytes.length >= 8) {
      final parsedValue = byteData.getFloat64(0, Endian.little);
      return parsedValue.isFinite ? parsedValue : 0;
    }
    if (bytes.length >= 4) {
      final parsedValue = byteData.getFloat32(0, Endian.little);
      return parsedValue.isFinite ? parsedValue : 0;
    }
    if (bytes.length >= 2) {
      return byteData.getInt16(0, Endian.little).toDouble();
    }
    return bytes.first.toDouble();
  }

  _EmgPayload? _parseEmgTextPayload(String textValue) {
    if (textValue.isEmpty) return null;

    if (textValue.startsWith('{') || textValue.startsWith('[')) {
      try {
        return _extractEmgPayloadFromJson(jsonDecode(textValue));
      } on Object {
        return null;
      }
    }

    final directValue = double.tryParse(textValue);
    if (directValue != null && directValue.isFinite) {
      return _EmgPayload(rawEmg: directValue, smoothEmg: directValue);
    }

    final rawValue = _parseLabelledValue(textValue, const [
      'rawEMG',
      'rawEmg',
      'raw_emg',
      'raw',
    ]);
    final smoothValue = _parseLabelledValue(textValue, const [
      'smoothEMG',
      'smoothEmg',
      'smooth_emg',
      'emg',
    ]);
    if (rawValue != null || smoothValue != null) {
      return _EmgPayload(
        rawEmg: rawValue ?? smoothValue ?? 0,
        smoothEmg: smoothValue ?? rawValue ?? 0,
      );
    }

    final commaSeparated = _parseCommaSeparatedValues(textValue);
    if (commaSeparated != null) return commaSeparated;

    return null;
  }

  _EmgPayload? _parseCommaSeparatedValues(String textValue) {
    if (!textValue.contains(',')) return null;

    final parts = textValue.split(',').map((s) => s.trim()).toList();
    if (parts.length != 2) return null;

    final smoothValue = double.tryParse(parts[0]);
    if (smoothValue != null && smoothValue.isFinite) {
      return _EmgPayload(rawEmg: smoothValue, smoothEmg: smoothValue);
    }

    return null;
  }

  _EmgPayload? _extractEmgPayloadFromJson(Object? decoded) {
    if (decoded is num && decoded.isFinite) {
      final value = decoded.toDouble();
      return _EmgPayload(rawEmg: value, smoothEmg: value);
    }
    if (decoded is Map) {
      final invalid = _extractInvalidMapValue(decoded);
      final activationValue = _extractNumericMapValue(decoded, const ['act']);
      final rawValue = _extractNumericMapValue(decoded, const [
        'rawEMG',
        'rawEmg',
        'raw_emg',
        'raw',
      ]);
      final smoothValue = _extractNumericMapValue(decoded, const [
        'smoothEMG',
        'smoothEmg',
        'smooth_emg',
        'emg',
      ]);
      if (activationValue != null) {
        return _EmgPayload(
          rawEmg: rawValue ?? activationValue,
          smoothEmg: activationValue,
          invalid: invalid,
        );
      }
      if (rawValue != null || smoothValue != null) {
        return _EmgPayload(
          rawEmg: rawValue ?? smoothValue ?? 0,
          smoothEmg: smoothValue ?? rawValue ?? 0,
          invalid: invalid,
        );
      }
    }
    return null;
  }

  double? _extractNumericMapValue(
    Map<dynamic, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is num && value.isFinite) return value.toDouble();
      if (value is String) {
        final parsedValue = double.tryParse(value);
        if (parsedValue != null && parsedValue.isFinite) {
          return parsedValue;
        }
      }
    }
    return null;
  }

  bool _extractInvalidMapValue(Map<dynamic, dynamic> map) {
    final value = map['invalid'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  @visibleForTesting
  ({double rawEmg, double smoothEmg, bool invalid})? parseEmgPayloadForTesting(
    List<int> value,
  ) {
    final payload = _parseEmgPayload(value);
    if (payload == null) return null;
    return (
      rawEmg: payload.rawEmg,
      smoothEmg: payload.smoothEmg,
      invalid: payload.invalid,
    );
  }

  @visibleForTesting
  void handleEmgValueForTesting(DeviceSide side, List<int> value) {
    _handleEmgValue(side, value);
  }

  double? _parseLabelledValue(String textValue, List<String> labels) {
    final labelPattern = labels.map(RegExp.escape).join('|');
    final match = RegExp(
      '(?:$labelPattern)\\s*[:=]\\s*(-?\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    ).firstMatch(textValue);
    if (match == null) return null;

    final parsedValue = double.tryParse(match.group(1)!);
    return parsedValue != null && parsedValue.isFinite ? parsedValue : null;
  }

  bool _looksLikeTextPayload(String textValue) {
    if (textValue.isEmpty) return false;
    return textValue.runes.every((codeUnit) {
      return codeUnit == 9 ||
          codeUnit == 10 ||
          codeUnit == 13 ||
          (codeUnit >= 32 && codeUnit <= 126);
    });
  }

  EmgDeviceConnection _deviceForSide(DeviceSide side) {
    return side == DeviceSide.left ? state.leftDevice : state.rightDevice;
  }

  BoundBleDevice? _boundDeviceForSide(DeviceSide side) {
    return side == DeviceSide.left
        ? state.leftBoundDevice
        : state.rightBoundDevice;
  }

  Future<void> _loadBoundDevices() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final leftId = preferences.getString(_leftDeviceIdKey);
      final leftName = preferences.getString(_leftDeviceNameKey);
      final rightId = preferences.getString(_rightDeviceIdKey);
      final rightName = preferences.getString(_rightDeviceNameKey);

      final leftBoundDevice = _boundDeviceFromStoredValues(leftId, leftName);
      final rightBoundDevice = _boundDeviceFromStoredValues(rightId, rightName);

      state = state.copyWith(
        leftBoundDevice: leftBoundDevice,
        rightBoundDevice: rightBoundDevice,
        leftDevice: leftBoundDevice == null
            ? state.leftDevice
            : state.leftDevice.copyWith(displayName: leftBoundDevice.name),
        rightDevice: rightBoundDevice == null
            ? state.rightDevice
            : state.rightDevice.copyWith(displayName: rightBoundDevice.name),
      );
    } on Object {
      // Device binding persistence should not block manual scanning.
    }
  }

  BoundBleDevice? _boundDeviceFromStoredValues(String? id, String? name) {
    if (id == null || id.trim().isEmpty) return null;
    final displayName = name == null || name.trim().isEmpty
        ? 'Bound BLE Device'
        : name;
    return BoundBleDevice(id: id, name: displayName);
  }

  Future<void> _saveBoundDevice(
    DeviceSide side,
    BoundBleDevice boundDevice,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    if (side == DeviceSide.left) {
      await preferences.setString(_leftDeviceIdKey, boundDevice.id);
      await preferences.setString(_leftDeviceNameKey, boundDevice.name);
      return;
    }

    await preferences.setString(_rightDeviceIdKey, boundDevice.id);
    await preferences.setString(_rightDeviceNameKey, boundDevice.name);
  }

  int _signalPercentFromRssi(int? rssi) {
    if (rssi == null) return 100;
    return ((rssi + 100) * 2).clamp(0, 100).toInt();
  }

  List<DiscoveredBleDevice> _mapScanResults(List<ScanResult> results) {
    final devices = results.map((result) {
      final platformName = result.device.platformName.trim();
      return DiscoveredBleDevice(
        id: result.device.remoteId.toString(),
        name: platformName.isEmpty ? 'Unnamed BLE Device' : platformName,
        rssi: result.rssi,
      );
    }).toList();
    devices.sort((a, b) {
      final aPreferred = a.name.toLowerCase() == 'my_emg';
      final bPreferred = b.name.toLowerCase() == 'my_emg';
      if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return devices;
  }

  Future<void> _stopScanQuietly() async {
    try {
      await FlutterBluePlus.stopScan();
    } on Object {
      // The platform channel may be unavailable in widget tests.
    }
  }
}
