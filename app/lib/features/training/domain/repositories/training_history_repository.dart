import 'package:myemg/features/training/domain/entities/session_summary.dart';

abstract class TrainingHistoryRepository {
  Future<List<SessionSummary>> loadSessions();

  Future<void> saveSession(SessionSummary summary);

  Future<void> saveSessions(List<SessionSummary> summaries);

  Future<void> clearSessions();

  Future<List<String>> loadExercises();

  Future<void> saveExercises(List<String> exercises);

  Future<List<String>> loadTargetMuscles();

  Future<void> saveTargetMuscles(List<String> muscles);

  Future<Map<String, List<String>>?> loadExercisesByMuscle();

  Future<void> saveExercisesByMuscle(
    Map<String, List<String>> exercisesByMuscle,
  );

  Future<String?> loadSelectedTargetMuscle();

  Future<void> saveSelectedTargetMuscle(String muscle);
}
