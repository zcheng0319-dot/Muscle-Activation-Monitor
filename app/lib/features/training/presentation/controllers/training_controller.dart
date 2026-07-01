import 'dart:async';

import 'package:flutter/foundation.dart';
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

enum EndSessionResult { saved, noSessionData, notEnoughValidData }

enum ExerciseEditResult { success, invalidName, storageFailure }

class TrainingController extends Notifier<TrainingState> {
  static const minimumValidSamplesToSave = 5;
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
          leftInvalid: deviceState.leftDevice.isInvalidSample,
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

    if (state.selectedExercise == null ||
        !state.targetMuscles.contains(state.selectedTargetMuscle) ||
        !state.exercises.contains(state.selectedExercise)) {
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
    final currentSample = _currentValidDeviceSample();
    if (currentSample != null) {
      _handleSample(currentSample);
    }
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
    ({
      double leftSmoothEmg,
      double leftRawEmg,
      bool leftConnected,
      bool leftInvalid,
    })
    deviceSample,
  ) {
    if (deviceSample.leftInvalid) return;

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

  Future<EndSessionResult> endSession() async {
    if (!state.isRunning && !state.hasSessionData) {
      return EndSessionResult.noSessionData;
    }

    if (!state.hasSessionData) {
      _timer?.cancel();
      _resetAccumulators();
      state = _sessionResetState();
      return EndSessionResult.notEnoughValidData;
    }

    if (state.sampleCount < minimumValidSamplesToSave) {
      _timer?.cancel();
      _resetAccumulators();
      state = _sessionResetState();
      return EndSessionResult.notEnoughValidData;
    }

    final selectedExercise = state.selectedExercise;
    if (selectedExercise == null) {
      return EndSessionResult.noSessionData;
    }

    final summary = SessionSummary(
      targetMuscle: state.selectedTargetMuscle,
      exerciseName: selectedExercise,
      durationSeconds: state.elapsedSeconds,
      repetitions: state.repetitions,
      leftAverage: state.leftAverage,
      rightAverage: state.rightAverage,
      leftPeak: state.leftPeak,
      rightPeak: state.rightPeak,
      balanceScore: state.balanceScore,
      createdAt: DateTime.now(),
    );
    final actionRankings = [summary, ...state.actionRankings];

    _timer?.cancel();
    _resetAccumulators();
    state = _sessionResetState(actionRankings: actionRankings);
    try {
      await ref.read(trainingHistoryRepositoryProvider).saveSession(summary);
    } on Object {
      // The session is kept in memory if local storage cannot be reached.
    }
    return EndSessionResult.saved;
  }

  void selectExercise(String exercise) {
    if (_locksExerciseChanges) return;
    if (!state.exercises.contains(exercise)) return;
    state = state.copyWith(selectedExercise: exercise);
  }

  void selectTargetMuscle(String muscle) {
    if (_locksExerciseChanges || !state.targetMuscles.contains(muscle)) return;

    final exercises = state.exercisesByMuscle[muscle] ?? const <String>[];
    state = state.copyWith(
      selectedTargetMuscle: muscle,
      selectedExercise: exercises.isEmpty ? null : exercises.first,
      clearSelectedExercise: exercises.isEmpty,
    );
    unawaited(_saveSelectedTargetMuscle(muscle));
  }

  bool addTargetMuscle(String name) {
    if (_locksExerciseChanges) return false;

    final trimmedName = name.trim();
    if (trimmedName.isEmpty ||
        state.targetMuscles.any(
          (muscle) => muscle.toLowerCase() == trimmedName.toLowerCase(),
        )) {
      return false;
    }

    final muscles = [...state.targetMuscles, trimmedName];
    final exercisesByMuscle = <String, List<String>>{
      ...state.exercisesByMuscle,
      trimmedName: const [],
    };
    state = state.copyWith(
      selectedTargetMuscle: trimmedName,
      targetMuscles: muscles,
      exercisesByMuscle: exercisesByMuscle,
      clearSelectedExercise: true,
    );
    unawaited(_saveMuscleCatalog(muscles, exercisesByMuscle, trimmedName));
    return true;
  }

  Future<ExerciseEditResult> renameTargetMuscle(
    String oldName,
    String newName,
  ) async {
    if (_locksExerciseChanges || !state.targetMuscles.contains(oldName)) {
      return ExerciseEditResult.invalidName;
    }

    final trimmedName = newName.trim();
    final duplicatesAnotherMuscle = state.targetMuscles.any(
      (muscle) =>
          muscle != oldName &&
          muscle.toLowerCase() == trimmedName.toLowerCase(),
    );
    if (trimmedName.isEmpty || duplicatesAnotherMuscle) {
      return ExerciseEditResult.invalidName;
    }

    final previousMuscles = state.targetMuscles;
    final previousExercisesByMuscle = state.exercisesByMuscle;
    final previousSessions = state.actionRankings;
    final previousSelectedMuscle = state.selectedTargetMuscle;
    final muscles = state.targetMuscles
        .map((muscle) => muscle == oldName ? trimmedName : muscle)
        .toList();
    final exercisesByMuscle = <String, List<String>>{};
    for (final muscle in state.targetMuscles) {
      exercisesByMuscle[muscle == oldName ? trimmedName : muscle] = [
        ...(state.exercisesByMuscle[muscle] ?? const <String>[]),
      ];
    }
    final sessions = state.actionRankings
        .map(
          (summary) => summary.targetMuscle == oldName
              ? summary.copyWith(targetMuscle: trimmedName)
              : summary,
        )
        .toList();
    final selectedMuscle = state.selectedTargetMuscle == oldName
        ? trimmedName
        : state.selectedTargetMuscle;

    final repository = ref.read(trainingHistoryRepositoryProvider);
    try {
      await repository.saveTargetMuscles(muscles);
      await repository.saveExercisesByMuscle(exercisesByMuscle);
      await repository.saveSessions(sessions);
      await repository.saveSelectedTargetMuscle(selectedMuscle);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to update saved sessions: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _rollbackMuscleMutation(
        repository,
        muscles: previousMuscles,
        exercisesByMuscle: previousExercisesByMuscle,
        sessions: previousSessions,
        selectedMuscle: previousSelectedMuscle,
      );
      return ExerciseEditResult.storageFailure;
    }

    state = state.copyWith(
      selectedTargetMuscle: selectedMuscle,
      targetMuscles: muscles,
      exercisesByMuscle: exercisesByMuscle,
      actionRankings: sessions,
    );
    return ExerciseEditResult.success;
  }

  Future<ExerciseEditResult> deleteTargetMuscle(String muscleName) async {
    if (_locksExerciseChanges || !state.targetMuscles.contains(muscleName)) {
      return ExerciseEditResult.invalidName;
    }

    final previousMuscles = state.targetMuscles;
    final previousExercisesByMuscle = state.exercisesByMuscle;
    final previousSessions = state.actionRankings;
    final previousSelectedMuscle = state.selectedTargetMuscle;
    var muscles = state.targetMuscles
        .where((muscle) => muscle != muscleName)
        .toList();
    final exercisesByMuscle = _copyExercisesByMuscle()..remove(muscleName);
    if (muscles.isEmpty) {
      muscles = const [defaultTargetMuscle];
      exercisesByMuscle[defaultTargetMuscle] = [
        ...(defaultExercisesByMuscle[defaultTargetMuscle] ?? const <String>[]),
      ];
    }
    final sessions = state.actionRankings
        .where((summary) => summary.targetMuscle != muscleName)
        .toList();
    final deletesSelection = state.selectedTargetMuscle == muscleName;
    final selectedMuscle = deletesSelection
        ? muscles.first
        : state.selectedTargetMuscle;
    final selectedExercises =
        exercisesByMuscle[selectedMuscle] ?? const <String>[];
    final selectedExercise = deletesSelection
        ? (selectedExercises.isEmpty ? null : selectedExercises.first)
        : state.selectedExercise;

    final repository = ref.read(trainingHistoryRepositoryProvider);
    try {
      await repository.saveTargetMuscles(muscles);
      await repository.saveExercisesByMuscle(exercisesByMuscle);
      await repository.saveSessions(sessions);
      await repository.saveSelectedTargetMuscle(selectedMuscle);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to update saved sessions: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _rollbackMuscleMutation(
        repository,
        muscles: previousMuscles,
        exercisesByMuscle: previousExercisesByMuscle,
        sessions: previousSessions,
        selectedMuscle: previousSelectedMuscle,
      );
      return ExerciseEditResult.storageFailure;
    }

    state = state.copyWith(
      selectedTargetMuscle: selectedMuscle,
      targetMuscles: muscles,
      exercisesByMuscle: exercisesByMuscle,
      selectedExercise: selectedExercise,
      clearSelectedExercise: selectedExercise == null,
      actionRankings: sessions,
    );
    return ExerciseEditResult.success;
  }

  bool addExercise(String name) {
    if (_locksExerciseChanges) return false;

    final trimmedName = name.trim();
    if (trimmedName.isEmpty || _containsExercise(trimmedName)) {
      return false;
    }

    final exercisesByMuscle = _copyExercisesByMuscle();
    exercisesByMuscle[state.selectedTargetMuscle] = [
      ...state.exercises,
      trimmedName,
    ];
    state = state.copyWith(
      exercisesByMuscle: exercisesByMuscle,
      selectedExercise: trimmedName,
    );
    unawaited(_saveExercisesByMuscle(exercisesByMuscle));
    return true;
  }

  Future<ExerciseEditResult> renameExercise(
    String oldName,
    String newName,
  ) async {
    if (_locksExerciseChanges) return ExerciseEditResult.invalidName;

    final trimmedName = newName.trim();
    if (trimmedName.isEmpty ||
        (trimmedName.toLowerCase() != oldName.toLowerCase() &&
            _containsExercise(trimmedName))) {
      return ExerciseEditResult.invalidName;
    }

    final previousExercisesByMuscle = state.exercisesByMuscle;
    final previousActionRankings = state.actionRankings;
    final exercises = state.exercises
        .map((exercise) => exercise == oldName ? trimmedName : exercise)
        .toList();
    final exercisesByMuscle = _copyExercisesByMuscle();
    exercisesByMuscle[state.selectedTargetMuscle] = exercises;
    final actionRankings = state.actionRankings
        .map(
          (summary) =>
              summary.targetMuscle == state.selectedTargetMuscle &&
                  summary.exerciseName == oldName
              ? summary.copyWith(exerciseName: trimmedName)
              : summary,
        )
        .toList();

    final repository = ref.read(trainingHistoryRepositoryProvider);
    try {
      await repository.saveExercisesByMuscle(exercisesByMuscle);
      await repository.saveSessions(actionRankings);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to update saved sessions: $error');
      debugPrintStack(stackTrace: stackTrace);
      try {
        await repository.saveExercisesByMuscle(previousExercisesByMuscle);
        await repository.saveSessions(previousActionRankings);
      } on Object catch (rollbackError, rollbackStackTrace) {
        debugPrint('Failed to roll back saved sessions: $rollbackError');
        debugPrintStack(stackTrace: rollbackStackTrace);
      }
      return ExerciseEditResult.storageFailure;
    }

    state = state.copyWith(
      exercisesByMuscle: exercisesByMuscle,
      selectedExercise: state.selectedExercise == oldName
          ? trimmedName
          : state.selectedExercise,
      actionRankings: actionRankings,
    );
    return ExerciseEditResult.success;
  }

  Future<bool> clearActionRankings() async {
    final remainingSessions = state.actionRankings
        .where((summary) => summary.targetMuscle != state.selectedTargetMuscle)
        .toList();
    try {
      final repository = ref.read(trainingHistoryRepositoryProvider);
      if (remainingSessions.isEmpty) {
        await repository.clearSessions();
      } else {
        await repository.saveSessions(remainingSessions);
      }
      state = state.copyWith(actionRankings: remainingSessions);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to update saved sessions: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<ExerciseEditResult> deleteExercise(String exerciseName) async {
    if (_locksExerciseChanges || !state.exercises.contains(exerciseName)) {
      return ExerciseEditResult.invalidName;
    }

    final previousExercisesByMuscle = state.exercisesByMuscle;
    final previousSessions = state.actionRankings;
    final exercisesByMuscle = _copyExercisesByMuscle();
    final remainingExercises = state.exercises
        .where((exercise) => exercise != exerciseName)
        .toList();
    exercisesByMuscle[state.selectedTargetMuscle] = remainingExercises;
    final remainingSessions = state.actionRankings
        .where(
          (summary) =>
              summary.targetMuscle != state.selectedTargetMuscle ||
              summary.exerciseName != exerciseName,
        )
        .toList();

    final repository = ref.read(trainingHistoryRepositoryProvider);
    try {
      await repository.saveExercisesByMuscle(exercisesByMuscle);
      await repository.saveSessions(remainingSessions);
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to update saved sessions: $error');
      debugPrintStack(stackTrace: stackTrace);
      try {
        await repository.saveExercisesByMuscle(previousExercisesByMuscle);
        await repository.saveSessions(previousSessions);
      } on Object catch (rollbackError, rollbackStackTrace) {
        debugPrint('Failed to roll back saved sessions: $rollbackError');
        debugPrintStack(stackTrace: rollbackStackTrace);
      }
      return ExerciseEditResult.storageFailure;
    }

    final deletesSelection = state.selectedExercise == exerciseName;
    state = state.copyWith(
      exercisesByMuscle: exercisesByMuscle,
      selectedExercise: deletesSelection && remainingExercises.isNotEmpty
          ? remainingExercises.first
          : state.selectedExercise,
      clearSelectedExercise: deletesSelection && remainingExercises.isEmpty,
      actionRankings: remainingSessions,
    );
    return ExerciseEditResult.success;
  }

  Future<bool> deleteSavedSession(SessionSummary summary) async {
    final sessions = [...state.actionRankings];
    final sessionIndex = sessions.indexWhere(
      (candidate) => identical(candidate, summary),
    );
    if (sessionIndex == -1) return false;

    sessions.removeAt(sessionIndex);
    try {
      await ref.read(trainingHistoryRepositoryProvider).saveSessions(sessions);
      state = state.copyWith(actionRankings: sessions);
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Failed to update saved sessions: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  void _resetAccumulators() {
    _leftTotal = 0;
    _rightTotal = 0;
    _sampleCount = 0;
    _readyForRep = true;
  }

  EmgSample? _currentValidDeviceSample() {
    final deviceState = ref.read(deviceConnectionControllerProvider);
    final device = deviceState.leftDevice;
    if (!device.connected ||
        device.isInvalidSample ||
        !device.smoothEmg.isFinite ||
        !device.rawEmg.isFinite) {
      return null;
    }

    return _normalizedDeviceSample(
      leftSmoothEmg: device.smoothEmg,
      leftConnected: true,
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
      final savedMuscles = await repository.loadTargetMuscles();
      final savedExercisesByMuscle = await repository.loadExercisesByMuscle();
      final savedSelectedMuscle = await repository.loadSelectedTargetMuscle();
      final legacyExercises = savedExercisesByMuscle == null
          ? await repository.loadExercises()
          : const <String>[];
      if (_isDisposed) return;

      final migratedLegacyData = savedExercisesByMuscle == null;
      final exercisesByMuscle = savedExercisesByMuscle == null
          ? _copyDefaultExercisesByMuscle()
          : _copyExercisesMap(savedExercisesByMuscle);
      final muscles = _mergeMuscleNames(
        savedMuscles.isEmpty ? defaultTargetMuscles : savedMuscles,
        [
          ...exercisesByMuscle.keys,
          ...sessions.map((summary) => summary.targetMuscle),
        ],
      );

      if (migratedLegacyData) {
        exercisesByMuscle[defaultTargetMuscle] = _mergeExerciseNames(
          exercisesByMuscle[defaultTargetMuscle] ?? const [],
          legacyExercises,
        );
      }
      for (final muscle in muscles) {
        exercisesByMuscle[muscle] = _mergeExerciseNames(
          exercisesByMuscle[muscle] ?? const [],
          sessions
              .where((summary) => summary.targetMuscle == muscle)
              .map((summary) => summary.exerciseName),
        );
      }

      final selectedMuscle =
          savedSelectedMuscle != null && muscles.contains(savedSelectedMuscle)
          ? savedSelectedMuscle
          : muscles.contains(defaultTargetMuscle)
          ? defaultTargetMuscle
          : muscles.first;
      final exercises = exercisesByMuscle[selectedMuscle] ?? const [];

      state = state.copyWith(
        selectedTargetMuscle: selectedMuscle,
        targetMuscles: muscles,
        exercisesByMuscle: exercisesByMuscle,
        actionRankings: sessions,
        selectedExercise: exercises.isEmpty ? null : exercises.first,
        clearSelectedExercise: exercises.isEmpty,
      );

      if (migratedLegacyData || savedMuscles.isEmpty) {
        unawaited(
          _saveMuscleCatalog(muscles, exercisesByMuscle, selectedMuscle),
        );
      } else if (savedSelectedMuscle != selectedMuscle) {
        unawaited(_saveSelectedTargetMuscle(selectedMuscle));
      }
    } on Object {
      // Keep the mock training UI usable even if local storage is unavailable.
    }
  }

  Future<void> _saveMuscleCatalog(
    List<String> muscles,
    Map<String, List<String>> exercisesByMuscle,
    String selectedMuscle,
  ) async {
    try {
      final repository = ref.read(trainingHistoryRepositoryProvider);
      await repository.saveTargetMuscles(muscles);
      await repository.saveExercisesByMuscle(exercisesByMuscle);
      await repository.saveSelectedTargetMuscle(selectedMuscle);
    } on Object {
      // Catalog edits still apply in memory if local storage is unavailable.
    }
  }

  Future<void> _rollbackMuscleMutation(
    TrainingHistoryRepository repository, {
    required List<String> muscles,
    required Map<String, List<String>> exercisesByMuscle,
    required List<SessionSummary> sessions,
    required String selectedMuscle,
  }) async {
    try {
      await repository.saveTargetMuscles(muscles);
      await repository.saveExercisesByMuscle(exercisesByMuscle);
      await repository.saveSessions(sessions);
      await repository.saveSelectedTargetMuscle(selectedMuscle);
    } on Object catch (rollbackError, rollbackStackTrace) {
      debugPrint('Failed to roll back saved sessions: $rollbackError');
      debugPrintStack(stackTrace: rollbackStackTrace);
    }
  }

  Future<void> _saveSelectedTargetMuscle(String muscle) async {
    try {
      await ref
          .read(trainingHistoryRepositoryProvider)
          .saveSelectedTargetMuscle(muscle);
    } on Object {
      // The active in-memory selection remains usable if storage fails.
    }
  }

  Future<void> _saveExercisesByMuscle(
    Map<String, List<String>> exercisesByMuscle,
  ) async {
    try {
      await ref
          .read(trainingHistoryRepositoryProvider)
          .saveExercisesByMuscle(exercisesByMuscle);
    } on Object {
      // Exercise edits remain usable in memory if storage fails.
    }
  }

  TrainingState _sessionResetState({List<SessionSummary>? actionRankings}) {
    return TrainingState(
      selectedTargetMuscle: state.selectedTargetMuscle,
      targetMuscles: state.targetMuscles,
      exercisesByMuscle: state.exercisesByMuscle,
      selectedExercise: state.selectedExercise,
      actionRankings: actionRankings ?? state.actionRankings,
      leftBaseline: state.leftBaseline,
      rightBaseline: state.rightBaseline,
      leftSessionMax: state.leftSessionMax,
      rightSessionMax: state.rightSessionMax,
      rawEmgSamples: state.rawEmgSamples,
    );
  }

  Map<String, List<String>> _copyExercisesByMuscle() {
    return _copyExercisesMap(state.exercisesByMuscle);
  }

  Map<String, List<String>> _copyDefaultExercisesByMuscle() {
    return _copyExercisesMap(defaultExercisesByMuscle);
  }

  Map<String, List<String>> _copyExercisesMap(
    Map<String, List<String>> source,
  ) {
    return source.map((muscle, exercises) => MapEntry(muscle, [...exercises]));
  }

  List<String> _mergeMuscleNames(
    Iterable<String> currentMuscles,
    Iterable<String> newMuscles,
  ) {
    final muscles = <String>[];
    for (final muscle in [...currentMuscles, ...newMuscles]) {
      final trimmedName = muscle.trim();
      final alreadyExists = muscles.any(
        (name) => name.toLowerCase() == trimmedName.toLowerCase(),
      );
      if (trimmedName.isNotEmpty && !alreadyExists) {
        muscles.add(trimmedName);
      }
    }
    return muscles.isEmpty ? [...defaultTargetMuscles] : muscles;
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
