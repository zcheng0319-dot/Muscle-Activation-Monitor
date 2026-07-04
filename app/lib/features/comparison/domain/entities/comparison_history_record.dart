import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';

class ComparisonTrialSummary {
  const ComparisonTrialSummary({
    required this.actionId,
    required this.actionName,
    required this.repCount,
    required this.medianRepMean,
    required this.medianRepP95,
    required this.missingSamples,
    required this.maximumClipRatio,
    required this.qualityPacketCount,
    this.loadKg,
    this.rir,
    this.plannedReps,
  });

  final String actionId;
  final String actionName;
  final int repCount;
  final double medianRepMean;
  final double medianRepP95;
  final int missingSamples;
  final double maximumClipRatio;
  final int qualityPacketCount;
  final double? loadKg;
  final int? rir;
  final int? plannedReps;

  factory ComparisonTrialSummary.fromTrial(ActionTrial trial) {
    final medianRepMean = trial.medianRepMean;
    if (!trial.isValid || medianRepMean == null) {
      throw const FormatException('Only valid trials can be saved.');
    }
    return ComparisonTrialSummary(
      actionId: trial.action.id,
      actionName: trial.action.name,
      repCount: trial.repCount,
      medianRepMean: medianRepMean,
      medianRepP95: _median(
        trial.reps.map((rep) => rep.p95AdjustedEnv).toList(),
      ),
      missingSamples: trial.totalMissingSamples,
      maximumClipRatio: trial.maximumClipRatio,
      qualityPacketCount: trial.qualityPacketCount,
      loadKg: trial.action.loadKg,
      rir: trial.action.rir,
      plannedReps: trial.action.plannedReps,
    );
  }

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'actionName': actionName,
    'repCount': repCount,
    'medianRepMean': medianRepMean,
    'medianRepP95': medianRepP95,
    'missingSamples': missingSamples,
    'maximumClipRatio': maximumClipRatio,
    'qualityPacketCount': qualityPacketCount,
    'loadKg': loadKg,
    'rir': rir,
    'plannedReps': plannedReps,
  };

  factory ComparisonTrialSummary.fromJson(Map<String, Object?> json) {
    return ComparisonTrialSummary(
      actionId: _requiredString(json, 'actionId'),
      actionName: _requiredString(json, 'actionName'),
      repCount: _requiredInt(json, 'repCount'),
      medianRepMean: _requiredDouble(json, 'medianRepMean'),
      medianRepP95: _requiredDouble(json, 'medianRepP95'),
      missingSamples: _requiredInt(json, 'missingSamples'),
      maximumClipRatio: _requiredDouble(json, 'maximumClipRatio'),
      qualityPacketCount: _requiredInt(json, 'qualityPacketCount'),
      loadKg: _optionalDouble(json, 'loadKg'),
      rir: _optionalInt(json, 'rir'),
      plannedReps: _optionalInt(json, 'plannedReps'),
    );
  }
}

class ComparisonHistoryRecord {
  const ComparisonHistoryRecord({
    required this.id,
    required this.completedAt,
    required this.targetMuscle,
    required this.baseline,
    required this.noise,
    required this.trials,
  });

  final String id;
  final DateTime completedAt;
  final String targetMuscle;
  final double baseline;
  final double noise;
  final List<ComparisonTrialSummary> trials;

  factory ComparisonHistoryRecord.fromCompletedSession(
    ComparisonSession session,
  ) {
    if (!session.isComplete || session.completedAt == null) {
      throw const FormatException('Only completed sessions can be saved.');
    }
    return ComparisonHistoryRecord(
      id: session.id,
      completedAt: session.completedAt!,
      targetMuscle: session.targetMuscle,
      baseline: session.baseline,
      noise: session.noise,
      trials: List.unmodifiable(
        session.trials.map(ComparisonTrialSummary.fromTrial),
      ),
    );
  }

  List<ComparisonTrialSummary> get rankedTrials {
    return [...trials]
      ..sort((a, b) => b.medianRepMean.compareTo(a.medianRepMean));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'completedAt': completedAt.toIso8601String(),
    'targetMuscle': targetMuscle,
    'baseline': baseline,
    'noise': noise,
    'trials': trials.map((trial) => trial.toJson()).toList(),
  };

  factory ComparisonHistoryRecord.fromJson(Map<String, Object?> json) {
    final completedAt = DateTime.tryParse(_requiredString(json, 'completedAt'));
    final rawTrials = json['trials'];
    if (completedAt == null || rawTrials is! List) {
      throw const FormatException('Invalid comparison history record.');
    }
    final trials = rawTrials
        .map(
          (trial) => ComparisonTrialSummary.fromJson(
            Map<String, Object?>.from(trial as Map),
          ),
        )
        .toList(growable: false);
    if (trials.isEmpty) {
      throw const FormatException('A history record needs at least one trial.');
    }
    return ComparisonHistoryRecord(
      id: _requiredString(json, 'id'),
      completedAt: completedAt,
      targetMuscle: _requiredString(json, 'targetMuscle'),
      baseline: _requiredDouble(json, 'baseline'),
      noise: _requiredDouble(json, 'noise'),
      trials: List.unmodifiable(trials),
    );
  }
}

double _median(List<double> values) {
  if (values.isEmpty) {
    throw const FormatException('A trial needs at least one repetition.');
  }
  values.sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) return values[middle];
  return (values[middle - 1] + values[middle]) / 2;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid history field: $key');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Invalid history field: $key');
  return value;
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid history field: $key');
  }
  return value.toDouble();
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('Invalid history field: $key');
  return value;
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw FormatException('Invalid history field: $key');
  }
  return value.toDouble();
}
