class ComparisonActionPlan {
  const ComparisonActionPlan({
    required this.id,
    required this.name,
    this.loadKg,
    this.rir,
    this.plannedReps,
  });

  final String id;
  final String name;
  final double? loadKg;
  final int? rir;
  final int? plannedReps;

  ComparisonActionPlan copyWith({
    String? id,
    String? name,
    double? loadKg,
    int? rir,
    int? plannedReps,
  }) {
    return ComparisonActionPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      loadKg: loadKg ?? this.loadKg,
      rir: rir ?? this.rir,
      plannedReps: plannedReps ?? this.plannedReps,
    );
  }
}

class ComparisonEnvelopeSample {
  const ComparisonEnvelopeSample({
    required this.deviceMs,
    required this.env,
    required this.adjustedEnv,
    required this.seq,
    required this.missingSamples,
  });

  final int deviceMs;
  final double env;
  final double adjustedEnv;
  final int seq;
  final int missingSamples;
}

class RepEmgResult {
  const RepEmgResult({
    required this.startDeviceMs,
    required this.endDeviceMs,
    required this.sampleCount,
    required this.meanAdjustedEnv,
    required this.p95AdjustedEnv,
  });

  final int startDeviceMs;
  final int endDeviceMs;
  final int sampleCount;
  final double meanAdjustedEnv;
  final double p95AdjustedEnv;

  int get durationMs => endDeviceMs - startDeviceMs;
}

class ActionTrial {
  const ActionTrial({
    required this.action,
    required this.samples,
    required this.reps,
    required this.recordedAt,
    required this.totalMissingSamples,
    required this.maximumClipRatio,
    required this.qualityPacketCount,
    this.correctedRepCount,
    this.invalidReason,
  });

  final ComparisonActionPlan action;
  final List<ComparisonEnvelopeSample> samples;
  final List<RepEmgResult> reps;
  final DateTime recordedAt;
  final int totalMissingSamples;
  final double maximumClipRatio;
  final int qualityPacketCount;
  final int? correctedRepCount;
  final String? invalidReason;

  int get repCount => reps.length;

  bool get isValid => invalidReason == null && reps.isNotEmpty;

  double? get medianRepMean {
    if (reps.isEmpty) return null;
    final values = reps.map((rep) => rep.meanAdjustedEnv).toList()..sort();
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }

  ActionTrial copyWith({List<RepEmgResult>? reps, int? correctedRepCount}) {
    return ActionTrial(
      action: action,
      samples: samples,
      reps: reps ?? this.reps,
      recordedAt: recordedAt,
      totalMissingSamples: totalMissingSamples,
      maximumClipRatio: maximumClipRatio,
      qualityPacketCount: qualityPacketCount,
      correctedRepCount: correctedRepCount ?? this.correctedRepCount,
      invalidReason: invalidReason,
    );
  }
}

class ComparisonSession {
  const ComparisonSession({
    required this.id,
    required this.targetMuscle,
    required this.startedAt,
    required this.baseline,
    required this.noise,
    required this.actions,
    required this.trials,
    this.completedAt,
    this.abortedReason,
  });

  final String id;
  final String targetMuscle;
  final DateTime startedAt;
  final DateTime? completedAt;
  final double baseline;
  final double noise;
  final List<ComparisonActionPlan> actions;
  final List<ActionTrial> trials;
  final String? abortedReason;

  bool get isComplete {
    return completedAt != null &&
        abortedReason == null &&
        trials.length == actions.length;
  }

  ComparisonSession copyWith({
    DateTime? completedAt,
    List<ActionTrial>? trials,
    String? abortedReason,
  }) {
    return ComparisonSession(
      id: id,
      targetMuscle: targetMuscle,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      baseline: baseline,
      noise: noise,
      actions: actions,
      trials: trials ?? this.trials,
      abortedReason: abortedReason ?? this.abortedReason,
    );
  }
}
