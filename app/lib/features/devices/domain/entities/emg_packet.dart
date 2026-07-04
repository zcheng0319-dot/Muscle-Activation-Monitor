import 'dart:convert';

enum EmgProtocolVersion { unknown, legacy, v2 }

sealed class EmgV2Packet {
  const EmgV2Packet();

  bool get identifiesV2Protocol;
}

class EmgSample extends EmgV2Packet {
  const EmgSample({
    required this.env,
    required this.deviceMs,
    required this.seq,
    this.missingSamples = 0,
    this.deviceRestarted = false,
  });

  final double env;
  final int deviceMs;
  final int seq;
  final int missingSamples;
  final bool deviceRestarted;

  @override
  bool get identifiesV2Protocol => true;

  EmgSample withTransportStatus({
    required int missingSamples,
    required bool deviceRestarted,
  }) {
    return EmgSample(
      env: env,
      deviceMs: deviceMs,
      seq: seq,
      missingSamples: missingSamples,
      deviceRestarted: deviceRestarted,
    );
  }
}

class EmgQuality extends EmgV2Packet {
  const EmgQuality({
    required this.deviceMs,
    required this.rawSamples,
    required this.nearRailSamples,
    required this.clipRatio,
  });

  final int deviceMs;
  final int rawSamples;
  final int nearRailSamples;
  final double clipRatio;

  @override
  bool get identifiesV2Protocol => false;
}

enum EmgCalibrationState { preparing, collectingRest, complete, failed }

class EmgCalibration extends EmgV2Packet {
  const EmgCalibration({
    required this.state,
    this.baseline,
    this.noise,
    this.quality,
    this.failureReason,
  });

  final EmgCalibrationState state;
  final int? baseline;
  final int? noise;
  final String? quality;
  final String? failureReason;

  @override
  bool get identifiesV2Protocol => true;
}

EmgV2Packet? decodeEmgV2Packet(List<int> bytes) {
  if (bytes.isEmpty) return null;

  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, dynamic> || decoded['v'] != 2) return null;

    return switch (decoded['type']) {
      'sample' => _decodeSample(decoded),
      'quality' => _decodeQuality(decoded),
      'calibration' => _decodeCalibration(decoded),
      _ => null,
    };
  } on Object {
    return null;
  }
}

EmgSample? _decodeSample(Map<String, dynamic> json) {
  final env = _finiteDouble(json['env']);
  final deviceMs = _uint32(json['deviceMs']);
  final seq = _uint32(json['seq']);
  if (env == null || env < 0 || deviceMs == null || seq == null) return null;

  return EmgSample(env: env, deviceMs: deviceMs, seq: seq);
}

EmgQuality? _decodeQuality(Map<String, dynamic> json) {
  final deviceMs = _uint32(json['deviceMs']);
  final rawSamples = _nonNegativeInt(json['rawSamples']);
  final nearRailSamples = _nonNegativeInt(json['nearRailSamples']);
  final clipRatio = _finiteDouble(json['clipRatio']);
  if (deviceMs == null ||
      rawSamples == null ||
      nearRailSamples == null ||
      nearRailSamples > rawSamples ||
      clipRatio == null ||
      clipRatio < 0 ||
      clipRatio > 1) {
    return null;
  }

  return EmgQuality(
    deviceMs: deviceMs,
    rawSamples: rawSamples,
    nearRailSamples: nearRailSamples,
    clipRatio: clipRatio,
  );
}

EmgCalibration? _decodeCalibration(Map<String, dynamic> json) {
  final state = switch (json['state']) {
    'preparing' => EmgCalibrationState.preparing,
    'collecting_rest' => EmgCalibrationState.collectingRest,
    'complete' => EmgCalibrationState.complete,
    'failed' => EmgCalibrationState.failed,
    _ => null,
  };
  if (state == null) return null;

  if (state == EmgCalibrationState.complete) {
    final baseline = _nonNegativeInt(json['baseline']);
    final noise = _nonNegativeInt(json['noise']);
    final quality = json['quality'];
    if (baseline == null ||
        noise == null ||
        quality is! String ||
        quality.trim().isEmpty) {
      return null;
    }
    return EmgCalibration(
      state: state,
      baseline: baseline,
      noise: noise,
      quality: quality,
    );
  }

  if (state == EmgCalibrationState.failed) {
    final reason = json['reason'];
    if (reason is! String || reason.trim().isEmpty) return null;
    return EmgCalibration(state: state, failureReason: reason);
  }

  return EmgCalibration(state: state);
}

double? _finiteDouble(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value.toDouble();
}

int? _nonNegativeInt(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value % 1 != 0) {
    return null;
  }
  return value.toInt();
}

int? _uint32(Object? value) {
  final parsed = _nonNegativeInt(value);
  if (parsed == null || parsed > 0xffffffff) return null;
  return parsed;
}
