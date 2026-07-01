import 'package:myemg/features/training/domain/entities/session_summary.dart';

typedef EmgSample = ({int left, int right});
typedef RawEmgSample = ({double left, double right});

const defaultTargetMuscle = 'Biceps';
const defaultTargetMuscles = ['Biceps', 'Triceps', 'Legs'];
const defaultExercisesByMuscle = <String, List<String>>{
  'Biceps': ['Bicep Curl', 'Hammer Curl'],
  'Triceps': ['Triceps Pushdown', 'Overhead Extension'],
  'Legs': ['Leg Extension', 'Squat'],
};
const defaultSelectedExercise = 'Bicep Curl';

class TrainingState {
  static const _averageTieTolerance = 0.001;

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
    this.leftBaseline = 0,
    this.rightBaseline = 0,
    this.leftSessionMax = 0,
    this.rightSessionMax = 0,
    this.selectedTargetMuscle = defaultTargetMuscle,
    this.targetMuscles = defaultTargetMuscles,
    this.exercisesByMuscle = defaultExercisesByMuscle,
    this.selectedExercise = defaultSelectedExercise,
    this.actionRankings = const [],
    this.rawSamples = const [],
    this.rawEmgSamples = const [],
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
  final double leftBaseline;
  final double rightBaseline;
  final double leftSessionMax;
  final double rightSessionMax;
  final String selectedTargetMuscle;
  final List<String> targetMuscles;
  final Map<String, List<String>> exercisesByMuscle;
  final String? selectedExercise;
  final List<SessionSummary> actionRankings;
  final List<EmgSample> rawSamples;
  final List<RawEmgSample> rawEmgSamples;

  int get difference => (leftActivation - rightActivation).abs();

  bool get hasSessionData => sampleCount > 0;

  String get targetMuscleLabel {
    final muscle = selectedTargetMuscle.trim();
    return muscle.isEmpty || !targetMuscles.contains(muscle)
        ? 'Muscle'
        : muscle;
  }

  List<String> get exercises =>
      exercisesByMuscle[selectedTargetMuscle] ?? const [];

  List<SessionSummary> get currentMuscleSessions => actionRankings
      .where((summary) => summary.targetMuscle == selectedTargetMuscle)
      .toList();

  int get balanceScore {
    if (!hasSessionData) return 0;
    return (100 - (leftAverage - rightAverage).abs())
        .round()
        .clamp(0, 100)
        .toInt();
  }

  List<SessionSummary> get sortedActionRankings {
    final rankings = _bestSummariesByExercise(currentMuscleSessions);
    return rankings.values.toList()..sort((a, b) {
      final averageDifference = b.leftAverage - a.leftAverage;
      if (averageDifference.abs() > _averageTieTolerance) {
        return averageDifference > 0 ? 1 : -1;
      }
      return b.peakActivation.compareTo(a.peakActivation);
    });
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
    double? leftBaseline,
    double? rightBaseline,
    double? leftSessionMax,
    double? rightSessionMax,
    String? selectedTargetMuscle,
    List<String>? targetMuscles,
    Map<String, List<String>>? exercisesByMuscle,
    String? selectedExercise,
    bool clearSelectedExercise = false,
    List<SessionSummary>? actionRankings,
    List<EmgSample>? rawSamples,
    List<RawEmgSample>? rawEmgSamples,
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
      leftBaseline: leftBaseline ?? this.leftBaseline,
      rightBaseline: rightBaseline ?? this.rightBaseline,
      leftSessionMax: leftSessionMax ?? this.leftSessionMax,
      rightSessionMax: rightSessionMax ?? this.rightSessionMax,
      selectedTargetMuscle: selectedTargetMuscle ?? this.selectedTargetMuscle,
      targetMuscles: targetMuscles ?? this.targetMuscles,
      exercisesByMuscle: exercisesByMuscle ?? this.exercisesByMuscle,
      selectedExercise: clearSelectedExercise
          ? null
          : selectedExercise ?? this.selectedExercise,
      actionRankings: actionRankings ?? this.actionRankings,
      rawSamples: rawSamples ?? this.rawSamples,
      rawEmgSamples: rawEmgSamples ?? this.rawEmgSamples,
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
    final averageDifference = candidate.leftAverage - existing.leftAverage;
    if (averageDifference.abs() > _averageTieTolerance) {
      return averageDifference > 0;
    }
    return candidate.peakActivation > existing.peakActivation;
  }
}

String liveActivationCopy(String targetMuscle) {
  return switch (targetMuscle.trim()) {
    'Biceps' => 'Live biceps activation',
    'Triceps' => 'Live triceps activation',
    'Legs' => 'Live leg muscle activation',
    final muscle when muscle.isNotEmpty =>
      'Live ${muscle.toLowerCase()} activation',
    _ => 'Live muscle activation',
  };
}

String contractionMuscleCopy(String targetMuscle) {
  return switch (targetMuscle.trim()) {
    'Biceps' => 'biceps',
    'Triceps' => 'triceps',
    'Legs' => 'leg muscles',
    final muscle when muscle.isNotEmpty => muscle.toLowerCase(),
    _ => 'muscles',
  };
}
