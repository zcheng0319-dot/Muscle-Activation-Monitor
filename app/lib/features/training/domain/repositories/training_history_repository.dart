import 'package:myemg/features/training/domain/entities/session_summary.dart';

abstract class TrainingHistoryRepository {
  Future<List<SessionSummary>> loadSessions();

  Future<void> saveSession(SessionSummary summary);

  Future<void> saveSessions(List<SessionSummary> summaries);

  Future<void> clearSessions();

  Future<List<String>> loadExercises();

  Future<void> saveExercises(List<String> exercises);
}
