import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/data/repositories/local_training_history_repository.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/domain/repositories/training_history_repository.dart';

final trainingHistoryRepositoryProvider = Provider<TrainingHistoryRepository>(
  (ref) => const LocalTrainingHistoryRepository(),
);

final trainingControllerProvider =
    NotifierProvider<TrainingController, TrainingState>(TrainingController.new);

class TrainingController extends Notifier<TrainingState> {
  static const _repActivationThreshold = 70;
  static const _repReleaseThreshold = 45;
  static const _maxRawSamples = 80;
  static const _maxRawWaveformSamples = 180;

  Timer? _timer;
  int _leftTotal = 0;
  int _rightTotal = 0;
  int _sampleCount = 0;
  bool _readyForRep = true;
  bool _isDisposed = false;

  @override
  TrainingState build() {
    _isDisposed = false;
    unawaited(_loadPersistedTrainingData());
    ref.listen(
      deviceConnectionControllerProvider.select(
        (deviceState) => (
          leftSmoothEmg: deviceState.leftDevice.connected
              ? deviceState.leftDevice.smoothEmg
              : 0.0,
          leftRawEmg: deviceState.leftDevice.connected
              ? deviceState.leftDevice.rawEmg
              : 0.0,
          leftConnected: deviceState.leftDevice.connected,
        ),
      ),
      (_, deviceSample) => _handleLiveDeviceActivation(deviceSample),
    );
    ref.onDispose(() {
      _isDisposed = true;
      _timer?.cancel();
    });
    return const TrainingState();
  }

  void toggleSession() {
    if (state.isRunning) {
      _timer?.cancel();
      state = state.copyWith(isRunning: false);
      return;
    }

    final startsNewSession = !state.hasSessionData && state.elapsedSeconds == 0;
    if (startsNewSession) {
      _resetAccumulators();
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
    state = state.copyWith(isRunning: true);
    _handleSample(_currentDeviceSample());
  }

  void calibrateRelax() {
    final deviceState = ref.read(deviceConnectionControllerProvider);
    state = state.copyWith(
      leftBaseline: deviceState.leftDevice.connected
          ? deviceState.leftDevice.smoothEmg
          : state.leftBaseline,
      rightBaseline: deviceState.rightDevice.connected
          ? deviceState.rightDevice.smoothEmg
          : state.rightBaseline,
    );
  }

  void calibrateMax() {
    final deviceState = ref.read(deviceConnectionControllerProvider);
    state = state.copyWith(
      leftSessionMax: deviceState.leftDevice.connected
          ? deviceState.leftDevice.smoothEmg
          : state.leftSessionMax,
      rightSessionMax: deviceState.rightDevice.connected
          ? deviceState.rightDevice.smoothEmg
          : state.rightSessionMax,
    );
  }

  void _handleLiveDeviceActivation(
    ({double leftSmoothEmg, double leftRawEmg, bool leftConnected})
    deviceSample,
  ) {
    final sample = _normalizedDeviceSample(
      leftSmoothEmg: deviceSample.leftSmoothEmg,
      leftConnected: deviceSample.leftConnected,
    );
    final rawEmgSamples = _nextRawEmgSamples(
      leftRawEmg: deviceSample.leftRawEmg,
      rightRawEmg: 0,
      leftConnected: deviceSample.leftConnected,
      rightConnected: false,
    );

    if (state.isRunning) {
      _handleSample(sample, rawEmgSamples: rawEmgSamples);
      return;
    }

    state = state.copyWith(
      leftActivation: sample.left,
      rightActivation: 0,
      rawEmgSamples: rawEmgSamples,
    );
  }

  void _handleSample(EmgSample sample, {List<RawEmgSample>? rawEmgSamples}) {
    _leftTotal += sample.left;
    _rightTotal += sample.right;
    _sampleCount++;

    var repetitions = state.repetitions;
    if (_readyForRep && sample.left >= _repActivationThreshold) {
      repetitions++;
      _readyForRep = false;
    } else if (!_readyForRep && sample.left <= _repReleaseThreshold) {
      _readyForRep = true;
    }

    final rawSamples = [...state.rawSamples, sample];
    final trimmedRawSamples = rawSamples.length > _maxRawSamples
        ? rawSamples.sublist(rawSamples.length - _maxRawSamples)
        : rawSamples;

    state = state.copyWith(
      leftActivation: sample.left,
      rightActivation: sample.right,
      leftPeak: sample.left > state.leftPeak ? sample.left : state.leftPeak,
      rightPeak: sample.right > state.rightPeak
          ? sample.right
          : state.rightPeak,
      leftAverage: _leftTotal / _sampleCount,
      rightAverage: _rightTotal / _sampleCount,
      sampleCount: _sampleCount,
      repetitions: repetitions,
      rawSamples: trimmedRawSamples,
      rawEmgSamples: rawEmgSamples,
    );
  }

  Future<void> endSession() async {
    if (!state.isRunning && !state.hasSessionData) return;

    if (!state.hasSessionData) {
      final selectedExercise = state.selectedExercise;
      final exercises = state.exercises;
      final actionRankings = state.actionRankings;

      _timer?.cancel();
      _resetAccumulators();
      state = TrainingState(
        selectedExercise: selectedExercise,
        exercises: exercises,
        actionRankings: actionRankings,
        leftBaseline: state.leftBaseline,
        rightBaseline: state.rightBaseline,
        leftSessionMax: state.leftSessionMax,
        rightSessionMax: state.rightSessionMax,
        rawEmgSamples: state.rawEmgSamples,
      );
      return;
    }

    final summary = SessionSummary(
      exerciseName: state.selectedExercise,
      durationSeconds: state.elapsedSeconds,
      repetitions: state.repetitions,
      leftAverage: state.leftAverage,
      rightAverage: state.rightAverage,
      leftPeak: state.leftPeak,
      rightPeak: state.rightPeak,
      balanceScore: state.balanceScore,
      createdAt: DateTime.now(),
    );
    final selectedExercise = state.selectedExercise;
    final exercises = state.exercises;
    final actionRankings = [summary, ...state.actionRankings];

    _timer?.cancel();
    _resetAccumulators();
    state = TrainingState(
      selectedExercise: selectedExercise,
      exercises: exercises,
      actionRankings: actionRankings,
      leftBaseline: state.leftBaseline,
      rightBaseline: state.rightBaseline,
      leftSessionMax: state.leftSessionMax,
      rightSessionMax: state.rightSessionMax,
      rawEmgSamples: state.rawEmgSamples,
    );
    try {
      await ref.read(trainingHistoryRepositoryProvider).saveSession(summary);
    } on Object {
      // The session is kept in memory if local storage cannot be reached.
    }
  }

  void selectExercise(String exercise) {
    if (_locksExerciseChanges) return;
    state = state.copyWith(selectedExercise: exercise);
  }

  bool addExercise(String name) {
    if (_locksExerciseChanges) return false;

    final trimmedName = name.trim();
    if (trimmedName.isEmpty || _containsExercise(trimmedName)) {
      return false;
    }

    state = state.copyWith(
      exercises: [...state.exercises, trimmedName],
      selectedExercise: trimmedName,
    );
    unawaited(_saveExercises(state.exercises));
    return true;
  }

  bool renameExercise(String oldName, String newName) {
    if (_locksExerciseChanges) return false;

    final trimmedName = newName.trim();
    if (trimmedName.isEmpty ||
        (trimmedName.toLowerCase() != oldName.toLowerCase() &&
            _containsExercise(trimmedName))) {
      return false;
    }

    final exercises = state.exercises
        .map((exercise) => exercise == oldName ? trimmedName : exercise)
        .toList();
    final actionRankings = state.actionRankings
        .map(
          (summary) => summary.exerciseName == oldName
              ? summary.copyWith(exerciseName: trimmedName)
              : summary,
        )
        .toList();

    state = state.copyWith(
      exercises: exercises,
      selectedExercise: state.selectedExercise == oldName
          ? trimmedName
          : state.selectedExercise,
      actionRankings: actionRankings,
    );
    unawaited(_saveExerciseRename(exercises, actionRankings));
    return true;
  }

  Future<void> clearActionRankings() async {
    state = state.copyWith(actionRankings: const []);
    try {
      await ref.read(trainingHistoryRepositoryProvider).clearSessions();
    } on Object {
      // The visible ranking is already cleared; storage can be retried later.
    }
  }

  void _resetAccumulators() {
    _leftTotal = 0;
    _rightTotal = 0;
    _sampleCount = 0;
    _readyForRep = true;
  }

  EmgSample _currentDeviceSample() {
    final deviceState = ref.read(deviceConnectionControllerProvider);
    return _normalizedDeviceSample(
      leftSmoothEmg: deviceState.leftDevice.smoothEmg,
      leftConnected: deviceState.leftDevice.connected,
    );
  }

  EmgSample _normalizedDeviceSample({
    required double leftSmoothEmg,
    required bool leftConnected,
  }) {
    return (
      left: leftConnected && leftSmoothEmg.isFinite
          ? leftSmoothEmg.round().clamp(0, 100).toInt()
          : 0,
      right: 0,
    );
  }

  List<RawEmgSample> _nextRawEmgSamples({
    required double leftRawEmg,
    required double rightRawEmg,
    required bool leftConnected,
    required bool rightConnected,
  }) {
    final rawSample = (
      left: leftConnected && leftRawEmg.isFinite ? leftRawEmg : 0.0,
      right: rightConnected && rightRawEmg.isFinite ? rightRawEmg : 0.0,
    );
    final rawEmgSamples = [...state.rawEmgSamples, rawSample];
    final trimmedRawEmgSamples = rawEmgSamples.length > _maxRawWaveformSamples
        ? rawEmgSamples.sublist(rawEmgSamples.length - _maxRawWaveformSamples)
        : rawEmgSamples;

    return trimmedRawEmgSamples;
  }

  bool _containsExercise(String name) {
    return state.exercises.any(
      (exercise) => exercise.toLowerCase() == name.toLowerCase(),
    );
  }

  bool get _locksExerciseChanges => state.isRunning || state.hasSessionData;

  Future<void> _loadPersistedTrainingData() async {
    try {
      final repository = ref.read(trainingHistoryRepositoryProvider);
      final sessions = await repository.loadSessions();
      final savedExercises = await repository.loadExercises();
      if (_isDisposed) return;

      final exercises = _mergeExerciseNames(state.exercises, [
        ...savedExercises,
        ...sessions.map((summary) => summary.exerciseName),
      ]);

      state = state.copyWith(
        exercises: exercises,
        actionRankings: sessions,
        selectedExercise: exercises.contains(state.selectedExercise)
            ? state.selectedExercise
            : exercises.first,
      );
    } on Object {
      // Keep the mock training UI usable even if local storage is unavailable.
    }
  }

  Future<void> _saveExercises(List<String> exercises) async {
    try {
      await ref
          .read(trainingHistoryRepositoryProvider)
          .saveExercises(exercises);
    } on Object {
      // Exercise edits still apply in memory if local storage is unavailable.
    }
  }

  Future<void> _saveExerciseRename(
    List<String> exercises,
    List<SessionSummary> actionRankings,
  ) async {
    try {
      final repository = ref.read(trainingHistoryRepositoryProvider);
      await repository.saveExercises(exercises);
      await repository.saveSessions(actionRankings);
    } on Object {
      // Rename stays visible in memory even if persistence fails.
    }
  }

  List<String> _mergeExerciseNames(
    List<String> currentExercises,
    Iterable<String> newExercises,
  ) {
    final exercises = [...currentExercises];
    for (final exercise in newExercises) {
      final trimmedName = exercise.trim();
      final alreadyExists = exercises.any(
        (name) => name.toLowerCase() == trimmedName.toLowerCase(),
      );
      if (trimmedName.isNotEmpty && !alreadyExists) {
        exercises.add(trimmedName);
      }
    }
    return exercises;
  }
}
