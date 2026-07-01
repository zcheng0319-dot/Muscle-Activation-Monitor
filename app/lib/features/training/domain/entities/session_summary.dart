class SessionSummary {
  const SessionSummary({
    this.targetMuscle = 'Biceps',
    required this.exerciseName,
    required this.durationSeconds,
    required this.repetitions,
    required this.leftAverage,
    required this.rightAverage,
    required this.leftPeak,
    required this.rightPeak,
    required this.balanceScore,
    this.createdAt,
  });

  final String targetMuscle;
  final String exerciseName;
  final int durationSeconds;
  final int repetitions;
  final double leftAverage;
  final double rightAverage;
  final int leftPeak;
  final int rightPeak;
  final int balanceScore;
  final DateTime? createdAt;

  int get averageActivation => leftAverage.round();

  int get peakActivation => leftPeak;

  SessionSummary copyWith({String? targetMuscle, String? exerciseName}) {
    return SessionSummary(
      targetMuscle: targetMuscle ?? this.targetMuscle,
      exerciseName: exerciseName ?? this.exerciseName,
      durationSeconds: durationSeconds,
      repetitions: repetitions,
      leftAverage: leftAverage,
      rightAverage: rightAverage,
      leftPeak: leftPeak,
      rightPeak: rightPeak,
      balanceScore: balanceScore,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'targetMuscle': targetMuscle,
      'exerciseName': exerciseName,
      'durationSeconds': durationSeconds,
      'repetitions': repetitions,
      'leftAverage': leftAverage,
      'rightAverage': rightAverage,
      'leftPeak': leftPeak,
      'rightPeak': rightPeak,
      'balanceScore': balanceScore,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory SessionSummary.fromJson(Map<String, Object?> json) {
    return SessionSummary(
      targetMuscle: json['targetMuscle'] as String? ?? 'Biceps',
      exerciseName: json['exerciseName'] as String? ?? 'Unknown',
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      repetitions: json['repetitions'] as int? ?? 0,
      leftAverage: (json['leftAverage'] as num?)?.toDouble() ?? 0,
      rightAverage: (json['rightAverage'] as num?)?.toDouble() ?? 0,
      leftPeak: json['leftPeak'] as int? ?? 0,
      rightPeak: json['rightPeak'] as int? ?? 0,
      balanceScore: json['balanceScore'] as int? ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}
