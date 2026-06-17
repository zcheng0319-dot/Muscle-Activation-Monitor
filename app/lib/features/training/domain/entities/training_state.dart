import 'package:myemg/features/training/domain/entities/session_summary.dart';

typedef EmgSample = ({int left, int right});

const defaultExerciseNames = ['Bicep Curl', 'Hammer Curl'];
const defaultSelectedExercise = 'Bicep Curl';

class TrainingState {
  const TrainingState({
    this.leftActivation = 0,
    this.rightActivation = 0,
    this.leftPeak = 0,
    this.rightPeak = 0,
    this.leftAverage = 0,
    this.rightAverage = 0,
    this.sampleCount = 0,
    this.repetitions = 0,
    this.elapsedSeconds = 0,
    this.isRunning = false,
    this.selectedExercise = defaultSelectedExercise,
    this.exercises = defaultExerciseNames,
    this.actionRankings = const [],
    this.rawSamples = const [],
  });

  final int leftActivation;
  final int rightActivation;
  final int leftPeak;
  final int rightPeak;
  final double leftAverage;
  final double rightAverage;
  final int sampleCount;
  final int repetitions;
  final int elapsedSeconds;
  final bool isRunning;
  final String selectedExercise;
  final List<String> exercises;
  final List<SessionSummary> actionRankings;
  final List<EmgSample> rawSamples;

  int get difference => (leftActivation - rightActivation).abs();

  bool get hasSessionData => sampleCount > 0;

  int get balanceScore {
    if (!hasSessionData) return 0;
    return (100 - (leftAverage - rightAverage).abs())
        .round()
        .clamp(0, 100)
        .toInt();
  }

  List<SessionSummary> get sortedActionRankings {
    final rankings = _bestSummariesByExercise(actionRankings);
    final currentSummary = currentSessionSummary;
    if (currentSummary != null) {
      rankings[currentSummary.exerciseName] = currentSummary;
    }

    return rankings.values.toList()
      ..sort((a, b) => b.averageActivation.compareTo(a.averageActivation));
  }

  SessionSummary? get currentSessionSummary {
    if (!hasSessionData) return null;

    return SessionSummary(
      exerciseName: selectedExercise,
      durationSeconds: elapsedSeconds,
      repetitions: repetitions,
      leftAverage: leftAverage,
      rightAverage: rightAverage,
      leftPeak: leftPeak,
      rightPeak: rightPeak,
      balanceScore: balanceScore,
    );
  }

  TrainingState copyWith({
    int? leftActivation,
    int? rightActivation,
    int? leftPeak,
    int? rightPeak,
    double? leftAverage,
    double? rightAverage,
    int? sampleCount,
    int? repetitions,
    int? elapsedSeconds,
    bool? isRunning,
    String? selectedExercise,
    List<String>? exercises,
    List<SessionSummary>? actionRankings,
    List<EmgSample>? rawSamples,
  }) {
    return TrainingState(
      leftActivation: leftActivation ?? this.leftActivation,
      rightActivation: rightActivation ?? this.rightActivation,
      leftPeak: leftPeak ?? this.leftPeak,
      rightPeak: rightPeak ?? this.rightPeak,
      leftAverage: leftAverage ?? this.leftAverage,
      rightAverage: rightAverage ?? this.rightAverage,
      sampleCount: sampleCount ?? this.sampleCount,
      repetitions: repetitions ?? this.repetitions,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      isRunning: isRunning ?? this.isRunning,
      selectedExercise: selectedExercise ?? this.selectedExercise,
      exercises: exercises ?? this.exercises,
      actionRankings: actionRankings ?? this.actionRankings,
      rawSamples: rawSamples ?? this.rawSamples,
    );
  }

  Map<String, SessionSummary> _bestSummariesByExercise(
    List<SessionSummary> summaries,
  ) {
    final bestSummaries = <String, SessionSummary>{};
    for (final summary in summaries) {
      final existing = bestSummaries[summary.exerciseName];
      if (existing == null || _isBetterRanking(summary, existing)) {
        bestSummaries[summary.exerciseName] = summary;
      }
    }
    return bestSummaries;
  }

  bool _isBetterRanking(SessionSummary candidate, SessionSummary existing) {
    final activationComparison = candidate.averageActivation.compareTo(
      existing.averageActivation,
    );
    if (activationComparison != 0) return activationComparison > 0;
    return candidate.peakActivation > existing.peakActivation;
  }
}
