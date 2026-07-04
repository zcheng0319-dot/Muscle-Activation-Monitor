import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/data/repositories/local_comparison_history_repository.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('keeps the newest eight completed records', () async {
    const repository = LocalComparisonHistoryRepository();

    for (var index = 0; index < 9; index++) {
      await repository.saveCompleted(_record(index));
    }
    final records = await repository.loadRecords();

    expect(records, hasLength(8));
    expect(records.first.id, 'session-8');
    expect(records.last.id, 'session-1');
    expect(records.any((record) => record.id == 'session-0'), isFalse);
  });

  test('stored history contains summaries and no sample arrays', () async {
    const repository = LocalComparisonHistoryRepository();

    await repository.saveCompleted(_record(1));

    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(
      LocalComparisonHistoryRepository.storageKey,
    );
    expect(stored, contains('Bicep Curl'));
    expect(stored, contains('medianRepMean'));
    expect(stored, isNot(contains('"samples"')));
  });

  test(
    'saving the same session ID replaces rather than duplicates it',
    () async {
      const repository = LocalComparisonHistoryRepository();

      await repository.saveCompleted(_record(1));
      await repository.saveCompleted(_record(1));

      expect(await repository.loadRecords(), hasLength(1));
    },
  );
}

ComparisonHistoryRecord _record(int index) {
  return ComparisonHistoryRecord(
    id: 'session-$index',
    completedAt: DateTime.utc(2026, 7, 4, 12, index),
    targetMuscle: 'Biceps',
    baseline: 100,
    noise: 1,
    trials: const [
      ComparisonTrialSummary(
        actionId: 'action.biceps.bicep-curl',
        actionName: 'Bicep Curl',
        repCount: 8,
        medianRepMean: 255,
        medianRepP95: 300,
        missingSamples: 0,
        maximumClipRatio: 0,
        qualityPacketCount: 8,
        loadKg: 10,
        rir: 2,
        plannedReps: 8,
      ),
    ],
  );
}
