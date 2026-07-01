import 'dart:convert';

import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/features/training/domain/repositories/training_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalTrainingHistoryRepository implements TrainingHistoryRepository {
  const LocalTrainingHistoryRepository();

  static const _sessionsKey = 'training_history.sessions';
  static const _exercisesKey = 'training_history.exercises';
  static const _musclesKey = 'training_history.muscles';
  static const _exercisesByMuscleKey = 'training_history.exercises_by_muscle';
  static const _selectedMuscleKey = 'training_history.selected_muscle';

  @override
  Future<List<SessionSummary>> loadSessions() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedSessions = preferences.getStringList(_sessionsKey) ?? const [];

    return encodedSessions
        .map(_decodeSummary)
        .whereType<SessionSummary>()
        .toList()
      ..sort(_compareNewestFirst);
  }

  @override
  Future<void> saveSession(SessionSummary summary) async {
    final sessions = await loadSessions();
    await saveSessions([summary, ...sessions]);
  }

  @override
  Future<void> saveSessions(List<SessionSummary> summaries) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedSessions = summaries
        .map((summary) => jsonEncode(summary.toJson()))
        .toList();
    await preferences.setStringList(_sessionsKey, encodedSessions);
  }

  @override
  Future<void> clearSessions() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionsKey);
  }

  @override
  Future<List<String>> loadExercises() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_exercisesKey) ?? const [];
  }

  @override
  Future<void> saveExercises(List<String> exercises) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_exercisesKey, exercises);
  }

  @override
  Future<List<String>> loadTargetMuscles() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(_musclesKey) ?? const [];
  }

  @override
  Future<void> saveTargetMuscles(List<String> muscles) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_musclesKey, muscles);
  }

  @override
  Future<Map<String, List<String>>?> loadExercisesByMuscle() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_exercisesByMuscleKey);
    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return decoded.map<String, List<String>>((key, value) {
        final exercises = value is List
            ? value.whereType<String>().toList()
            : <String>[];
        return MapEntry(key.toString(), exercises);
      });
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> saveExercisesByMuscle(
    Map<String, List<String>> exercisesByMuscle,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _exercisesByMuscleKey,
      jsonEncode(exercisesByMuscle),
    );
  }

  @override
  Future<String?> loadSelectedTargetMuscle() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_selectedMuscleKey);
  }

  @override
  Future<void> saveSelectedTargetMuscle(String muscle) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_selectedMuscleKey, muscle);
  }

  SessionSummary? _decodeSummary(String encodedSummary) {
    try {
      final decoded = jsonDecode(encodedSummary);
      if (decoded is! Map) return null;
      return SessionSummary.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }

  static int _compareNewestFirst(SessionSummary a, SessionSummary b) {
    final aCreatedAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bCreatedAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bCreatedAt.compareTo(aCreatedAt);
  }
}
