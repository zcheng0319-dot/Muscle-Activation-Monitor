import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/training/data/datasources/mock_emg_datasource.dart';
import 'package:myemg/features/training/data/repositories/local_training_history_repository.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/domain/repositories/training_history_repository.dart';

final mockEmgDataSourceProvider = Provider((ref) => MockEmgDataSource());
final trainingHistoryRepositoryProvider = Provider<TrainingHistoryRepository>(
  (ref) => const LocalTrainingHistoryRepository(),
);

final trainingControllerProvider =
    NotifierProvider<TrainingController, TrainingState>(TrainingController.new);

class TrainingController extends Notifier<TrainingState> {
  static const _repActivationThreshold = 70;
  static const _repReleaseThreshold = 45;
  static const _maxRawSamples = 80;

  StreamSubscription<(int, int)>? _subscription;
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
    ref.onDispose(() {
      _isDisposed = true;
      _subscription?.cancel();
      _timer?.cancel();
    });
    return const TrainingState();
  }

  void toggleSession() {
    if (state.isRunning) {
      _subscription?.pause();
      _timer?.cancel();
      state = state.copyWith(isRunning: false);
      return;
    }

    final startsNewSession = _subscription == null;
    if (startsNewSession) {
      _resetAccumulators();
      _subscription = ref
          .read(mockEmgDataSourceProvider)
          .watchActivation()
          .listen(_handleSample);
    } else {
      _subscription?.resume();
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
    state = state.copyWith(isRunning: true);
  }

  void _handleSample((int, int) sample) {
    _leftTotal += sample.$1;
    _rightTotal += sample.$2;
    _sampleCount++;

    final bilateralActivation = (sample.$1 + sample.$2) / 2;
    var repetitions = state.repetitions;
    if (_readyForRep && bilateralActivation >= _repActivationThreshold) {
      repetitions++;
      _readyForRep = false;
    } else if (!_readyForRep && bilateralActivation <= _repReleaseThreshold) {
      _readyForRep = true;
    }

    final rawSamples = [
      ...state.rawSamples,
      (left: sample.$1, right: sample.$2),
    ];
    final trimmedRawSamples = rawSamples.length > _maxRawSamples
        ? rawSamples.sublist(rawSamples.length - _maxRawSamples)
        : rawSamples;

    state = state.copyWith(
      leftActivation: sample.$1,
      rightActivation: sample.$2,
      leftPeak: sample.$1 > state.leftPeak ? sample.$1 : state.leftPeak,
      rightPeak: sample.$2 > state.rightPeak ? sample.$2 : state.rightPeak,
      leftAverage: _leftTotal / _sampleCount,
      rightAverage: _rightTotal / _sampleCount,
      sampleCount: _sampleCount,
      repetitions: repetitions,
      rawSamples: trimmedRawSamples,
    );
  }

  Future<void> endSession() async {
    if (!state.hasSessionData) return;

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

    _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _resetAccumulators();
    state = TrainingState(
      selectedExercise: selectedExercise,
      exercises: exercises,
      actionRankings: actionRankings,
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
