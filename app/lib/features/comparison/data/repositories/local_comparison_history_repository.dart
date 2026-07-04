import 'dart:convert';

import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:myemg/features/comparison/domain/repositories/comparison_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalComparisonHistoryRepository implements ComparisonHistoryRepository {
  const LocalComparisonHistoryRepository();

  static const storageKey = 'comparison.history.v1';
  static const schemaVersion = 1;
  static const maximumRecords = 8;

  @override
  Future<List<ComparisonHistoryRecord>> loadRecords() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(storageKey);
    if (stored == null) return const [];

    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map ||
          decoded['schemaVersion'] != schemaVersion ||
          decoded['records'] is! List) {
        return const [];
      }
      final records = (decoded['records'] as List)
          .map(
            (record) => ComparisonHistoryRecord.fromJson(
              Map<String, Object?>.from(record as Map),
            ),
          )
          .toList(growable: false);
      records.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      return List.unmodifiable(records.take(maximumRecords));
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> saveCompleted(ComparisonHistoryRecord record) async {
    final records = [...await loadRecords()]
      ..removeWhere((existing) => existing.id == record.id)
      ..add(record)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    final retained = records.take(maximumRecords).toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      storageKey,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'records': retained.map((entry) => entry.toJson()).toList(),
      }),
    );
    if (!saved) {
      throw StateError('Comparison history could not be saved.');
    }
  }
}
