import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';
import 'package:myemg/features/comparison/domain/services/rep_segmenter.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_history_controller.dart';
import 'package:myemg/features/devices/domain/entities/emg_packet.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';

final comparisonControllerProvider =
    NotifierProvider<ComparisonController, ComparisonState>(
      ComparisonController.new,
    );

enum ComparisonPhase {
  setup,
  calibrating,
  ready,
  recording,
  review,
  betweenActions,
  completed,
  aborted,
}

class ComparisonState {
  const ComparisonState({
    this.phase = ComparisonPhase.setup,
    this.targetMuscle = '',
    this.actions = const [],
    this.currentActionIndex = 0,
    this.baseline,
    this.noise,
    this.pendingTrial,
    this.completedTrials = const [],
    this.session,
    this.errorMessage,
  });

  final ComparisonPhase phase;
  final String targetMuscle;
  final List<ComparisonActionPlan> actions;
  final int currentActionIndex;
  final double? baseline;
  final double? noise;
  final ActionTrial? pendingTrial;
  final List<ActionTrial> completedTrials;
  final ComparisonSession? session;
  final String? errorMessage;

  ComparisonActionPlan? get currentAction {
    if (currentActionIndex < 0 || currentActionIndex >= actions.length) {
      return null;
    }
    return actions[currentActionIndex];
  }

  bool get actionOrderLocked => phase != ComparisonPhase.setup;

  ComparisonState copyWith({
    ComparisonPhase? phase,
    String? targetMuscle,
    List<ComparisonActionPlan>? actions,
    int? currentActionIndex,
    double? baseline,
    bool clearBaseline = false,
    double? noise,
    bool clearNoise = false,
    ActionTrial? pendingTrial,
    bool clearPendingTrial = false,
    List<ActionTrial>? completedTrials,
    ComparisonSession? session,
    bool clearSession = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ComparisonState(
      phase: phase ?? this.phase,
      targetMuscle: targetMuscle ?? this.targetMuscle,
      actions: actions ?? this.actions,
      currentActionIndex: currentActionIndex ?? this.currentActionIndex,
      baseline: clearBaseline ? null : baseline ?? this.baseline,
      noise: clearNoise ? null : noise ?? this.noise,
      pendingTrial: clearPendingTrial
          ? null
          : pendingTrial ?? this.pendingTrial,
      completedTrials: completedTrials ?? this.completedTrials,
      session: clearSession ? null : session ?? this.session,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ComparisonController extends Notifier<ComparisonState> {
  final RepSegmenter _segmenter = const RepSegmenter();
  final _recordingSamples = <ComparisonEnvelopeSample>[];
  StreamSubscription<EmgSample>? _sampleSubscription;
  StreamSubscription<EmgQuality>? _qualitySubscription;
  StreamSubscription<EmgCalibration>? _calibrationSubscription;
  Timer? _calibrationTimeout;
  static const double kMaximumActionClipRatio = 0.05;

  int _missingSamples = 0;
  double _maximumClipRatio = 0;
  int _qualityPacketCount = 0;

  @override
  ComparisonState build() {
    final deviceController = ref.read(
      deviceConnectionControllerProvider.notifier,
    );
    _sampleSubscription = deviceController
        .sampleStream(DeviceSide.left)
        .listen(_handleSample);
    _qualitySubscription = deviceController
        .qualityStream(DeviceSide.left)
        .listen(_handleQuality);
    _calibrationSubscription = deviceController
        .calibrationStream(DeviceSide.left)
        .listen(_handleCalibration);

    ref.listen(deviceConnectionControllerProvider, (previous, next) {
      final wasConnected = previous?.leftDevice.connected ?? false;
      if (wasConnected && !next.leftDevice.connected && _hasActiveComparison) {
        abort('device_disconnected');
      }
    });

    ref.onDispose(() {
      unawaited(_sampleSubscription?.cancel());
      unawaited(_qualitySubscription?.cancel());
      unawaited(_calibrationSubscription?.cancel());
      _calibrationTimeout?.cancel();
    });

    return const ComparisonState();
  }

  bool get _hasActiveComparison {
    return state.phase != ComparisonPhase.setup &&
        state.phase != ComparisonPhase.completed &&
        state.phase != ComparisonPhase.aborted;
  }

  bool configure({
    required String targetMuscle,
    required List<ComparisonActionPlan> actions,
  }) {
    if (state.phase != ComparisonPhase.setup &&
        state.phase != ComparisonPhase.completed &&
        state.phase != ComparisonPhase.aborted) {
      return false;
    }
    final normalizedMuscle = targetMuscle.trim();
    final validActions = actions
        .where(
          (action) =>
              action.id.trim().isNotEmpty && action.name.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (normalizedMuscle.isEmpty ||
        validActions.length < 2 ||
        validActions.length > 4) {
      return false;
    }
    if (validActions.map((action) => action.id).toSet().length !=
        validActions.length) {
      return false;
    }

    _resetRecording();
    _calibrationTimeout?.cancel();
    state = ComparisonState(
      targetMuscle: normalizedMuscle,
      actions: validActions,
    );
    return true;
  }

  bool reorderAction(int oldIndex, int newIndex) {
    if (state.phase != ComparisonPhase.setup ||
        oldIndex < 0 ||
        oldIndex >= state.actions.length ||
        newIndex < 0 ||
        newIndex >= state.actions.length) {
      return false;
    }

    final reordered = [...state.actions];
    final action = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, action);
    state = state.copyWith(actions: reordered, clearError: true);
    return true;
  }

  Future<bool> beginRestCalibration() async {
    if (state.phase != ComparisonPhase.setup ||
        state.actions.length < 2 ||
        state.targetMuscle.isEmpty) {
      return false;
    }

    final deviceState = ref.read(deviceConnectionControllerProvider).leftDevice;
    if (!deviceState.supportsComparison) {
      state = state.copyWith(
        errorMessage: deviceState.firmwareUpdateRequired
            ? 'firmware_update_required'
            : 'v2_device_not_ready',
      );
      return false;
    }

    state = state.copyWith(
      phase: ComparisonPhase.calibrating,
      clearBaseline: true,
      clearNoise: true,
      clearSession: true,
      clearError: true,
    );
    _startCalibrationTimeout();
    final sent = await ref
        .read(deviceConnectionControllerProvider.notifier)
        .sendRestCalibrationCommand();
    if (!sent && state.phase == ComparisonPhase.calibrating) {
      _calibrationTimeout?.cancel();
      state = state.copyWith(
        phase: ComparisonPhase.setup,
        errorMessage: 'calibration_command_failed',
      );
    }
    return sent;
  }

  bool cancelCalibration() {
    if (state.phase != ComparisonPhase.calibrating) return false;
    _calibrationTimeout?.cancel();
    state = state.copyWith(
      phase: ComparisonPhase.setup,
      clearBaseline: true,
      clearNoise: true,
      clearSession: true,
      clearError: true,
    );
    return true;
  }

  bool startCurrentAction() {
    if (state.phase != ComparisonPhase.ready &&
        state.phase != ComparisonPhase.betweenActions) {
      return false;
    }
    if (state.currentAction == null ||
        state.baseline == null ||
        state.noise == null) {
      return false;
    }

    _resetRecording();
    state = state.copyWith(
      phase: ComparisonPhase.recording,
      clearPendingTrial: true,
      clearError: true,
    );
    return true;
  }

  bool finishCurrentAction() {
    if (state.phase != ComparisonPhase.recording ||
        state.currentAction == null ||
        state.noise == null) {
      return false;
    }

    final segmentation = _segmenter.segment(
      samples: _recordingSamples,
      noise: state.noise!,
    );
    final trial = ActionTrial(
      action: state.currentAction!,
      samples: List.unmodifiable(_recordingSamples),
      reps: List.unmodifiable(segmentation.reps),
      recordedAt: DateTime.now(),
      totalMissingSamples: _missingSamples,
      maximumClipRatio: _maximumClipRatio,
      qualityPacketCount: _qualityPacketCount,
      invalidReason: _trialInvalidReason(
        segmentation.failureReason,
        segmentation.confidenceSufficient,
      ),
    );
    state = state.copyWith(
      phase: ComparisonPhase.review,
      pendingTrial: trial,
      errorMessage: segmentation.failureReason,
      clearError: segmentation.failureReason == null,
    );
    return true;
  }

  bool correctRepCount(int requestedCount) {
    final trial = state.pendingTrial;
    if (state.phase != ComparisonPhase.review ||
        trial == null ||
        !trial.isValid ||
        state.noise == null) {
      return false;
    }

    final segmentation = _segmenter.segment(
      samples: trial.samples,
      noise: state.noise!,
      requestedCount: requestedCount,
    );
    if (!segmentation.requestedCountMatched) {
      state = state.copyWith(
        errorMessage:
            segmentation.failureReason ?? 'requested_count_unavailable',
      );
      return false;
    }
    if (!segmentation.confidenceSufficient) {
      state = state.copyWith(errorMessage: 'low_confidence');
      return false;
    }

    state = state.copyWith(
      pendingTrial: trial.copyWith(
        reps: List.unmodifiable(segmentation.reps),
        correctedRepCount: requestedCount,
      ),
      clearError: true,
    );
    return true;
  }

  bool acceptCurrentAction() {
    final trial = state.pendingTrial;
    final session = state.session;
    if (state.phase != ComparisonPhase.review ||
        trial == null ||
        !trial.isValid ||
        session == null) {
      return false;
    }

    final completedTrials = [...state.completedTrials, trial];
    final updatedSession = session.copyWith(trials: completedTrials);
    final isLastAction = state.currentActionIndex == state.actions.length - 1;

    if (isLastAction) {
      final completedSession = updatedSession.copyWith(
        completedAt: DateTime.now(),
      );
      state = state.copyWith(
        phase: ComparisonPhase.completed,
        completedTrials: completedTrials,
        session: completedSession,
        clearPendingTrial: true,
        clearError: true,
      );
      unawaited(_saveCompletedHistory(completedSession));
      return true;
    }

    state = state.copyWith(
      phase: ComparisonPhase.betweenActions,
      currentActionIndex: state.currentActionIndex + 1,
      completedTrials: completedTrials,
      session: updatedSession,
      clearPendingTrial: true,
      clearError: true,
    );
    _resetRecording();
    return true;
  }

  bool discardAndRetryCurrentAction() {
    if (state.phase != ComparisonPhase.review) return false;
    _resetRecording();
    state = state.copyWith(
      phase: ComparisonPhase.ready,
      clearPendingTrial: true,
      clearError: true,
    );
    return true;
  }

  void abort(String reason) {
    final normalizedReason = reason.trim().isEmpty ? 'aborted' : reason.trim();
    final abortedSession = state.session?.copyWith(
      abortedReason: normalizedReason,
    );
    _calibrationTimeout?.cancel();
    _resetRecording();
    state = state.copyWith(
      phase: ComparisonPhase.aborted,
      session: abortedSession,
      errorMessage: normalizedReason,
      clearPendingTrial: true,
    );
  }

  void _handleSample(EmgSample sample) {
    if (!_hasActiveComparison) return;
    if (sample.deviceRestarted) {
      abort('device_restarted');
      return;
    }
    if (state.phase != ComparisonPhase.recording || state.baseline == null) {
      return;
    }

    _missingSamples += sample.missingSamples;
    _recordingSamples.add(
      ComparisonEnvelopeSample(
        deviceMs: sample.deviceMs,
        env: sample.env,
        adjustedEnv: math.max(0, sample.env - state.baseline!),
        seq: sample.seq,
        missingSamples: sample.missingSamples,
      ),
    );
  }

  void _handleQuality(EmgQuality quality) {
    if (state.phase != ComparisonPhase.recording) return;
    _qualityPacketCount++;
    _maximumClipRatio = math.max(_maximumClipRatio, quality.clipRatio);
  }

  void _handleCalibration(EmgCalibration calibration) {
    if (state.phase != ComparisonPhase.calibrating) return;

    switch (calibration.state) {
      case EmgCalibrationState.preparing:
      case EmgCalibrationState.collectingRest:
        return;
      case EmgCalibrationState.failed:
        _calibrationTimeout?.cancel();
        state = state.copyWith(
          phase: ComparisonPhase.setup,
          errorMessage: calibration.failureReason ?? 'calibration_failed',
        );
        return;
      case EmgCalibrationState.complete:
        _calibrationTimeout?.cancel();
        final baseline = calibration.baseline;
        final noise = calibration.noise;
        if (baseline == null || noise == null) {
          state = state.copyWith(
            phase: ComparisonPhase.setup,
            errorMessage: 'invalid_calibration_result',
          );
          return;
        }
        if (calibration.quality != 'good') {
          state = state.copyWith(
            phase: ComparisonPhase.setup,
            errorMessage: 'calibration_quality_not_good',
          );
          return;
        }
        final now = DateTime.now();
        final session = ComparisonSession(
          id: now.microsecondsSinceEpoch.toString(),
          targetMuscle: state.targetMuscle,
          startedAt: now,
          baseline: baseline.toDouble(),
          noise: noise.toDouble(),
          actions: List.unmodifiable(state.actions),
          trials: const [],
        );
        state = state.copyWith(
          phase: ComparisonPhase.ready,
          baseline: baseline.toDouble(),
          noise: noise.toDouble(),
          session: session,
          currentActionIndex: 0,
          completedTrials: const [],
          clearPendingTrial: true,
          clearError: true,
        );
        return;
    }
  }

  void _resetRecording() {
    _recordingSamples.clear();
    _missingSamples = 0;
    _maximumClipRatio = 0;
    _qualityPacketCount = 0;
  }

  String? _trialInvalidReason(
    String? segmentationFailure,
    bool confidenceSufficient,
  ) {
    if (_missingSamples > 0) return 'packet_loss_detected';
    if (_maximumClipRatio > kMaximumActionClipRatio) return 'clipping_detected';
    if (_qualityPacketCount == 0) return 'quality_unavailable';
    if (segmentationFailure != null) return segmentationFailure;
    if (!confidenceSufficient) return 'low_confidence';
    return null;
  }

  void _startCalibrationTimeout() {
    _calibrationTimeout?.cancel();
    _calibrationTimeout = Timer(
      const Duration(seconds: 10),
      _handleCalibrationTimeout,
    );
  }

  void _handleCalibrationTimeout() {
    if (state.phase != ComparisonPhase.calibrating) return;
    state = state.copyWith(
      phase: ComparisonPhase.setup,
      clearBaseline: true,
      clearNoise: true,
      clearSession: true,
      errorMessage: 'calibration_timeout',
    );
  }

  Future<void> _saveCompletedHistory(ComparisonSession session) async {
    try {
      await ref
          .read(comparisonHistoryRepositoryProvider)
          .saveCompleted(ComparisonHistoryRecord.fromCompletedSession(session));
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to save completed comparison: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @visibleForTesting
  void handleSampleForTesting(EmgSample sample) => _handleSample(sample);

  @visibleForTesting
  void handleQualityForTesting(EmgQuality quality) => _handleQuality(quality);

  @visibleForTesting
  void beginCalibrationForTesting() {
    state = state.copyWith(phase: ComparisonPhase.calibrating);
  }

  @visibleForTesting
  void handleCalibrationForTesting(EmgCalibration calibration) {
    _handleCalibration(calibration);
  }

  @visibleForTesting
  void triggerCalibrationTimeoutForTesting() => _handleCalibrationTimeout();
}
