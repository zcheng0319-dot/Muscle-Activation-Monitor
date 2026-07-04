import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';

abstract interface class ComparisonHistoryRepository {
  Future<List<ComparisonHistoryRecord>> loadRecords();

  Future<void> saveCompleted(ComparisonHistoryRecord record);
}
