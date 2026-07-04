import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_history_controller.dart';
import 'package:myemg/features/comparison/presentation/pages/recent_comparisons_page.dart';

void main() {
  testWidgets('history list opens a read-only session detail', (tester) async {
    final records = [
      _record(
        id: 'recent',
        completedAt: DateTime.utc(2026, 7, 4, 12),
        firstValue: 200,
        secondValue: 300,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comparisonHistoryControllerProvider.overrideWith(
            () => _FixedHistoryController(records),
          ),
        ],
        child: const MaterialApp(home: RecentComparisonsPage()),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('recent-comparisons-list')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('comparison-history-recent')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('comparison-history-detail')),
      findsOneWidget,
    );
    expect(
      find.textContaining('only to this electrode placement'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Hammer Curl')).dy,
      lessThan(tester.getTopLeft(find.text('Bicep Curl')).dy),
    );
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.textContaining('Clear'), findsNothing);
  });
}

ComparisonHistoryRecord _record({
  required String id,
  required DateTime completedAt,
  required double firstValue,
  required double secondValue,
}) {
  return ComparisonHistoryRecord(
    id: id,
    completedAt: completedAt,
    targetMuscle: 'Biceps',
    baseline: 100,
    noise: 1,
    trials: [
      ComparisonTrialSummary(
        actionId: 'curl',
        actionName: 'Bicep Curl',
        repCount: 8,
        medianRepMean: firstValue,
        medianRepP95: firstValue * 1.2,
        missingSamples: 0,
        maximumClipRatio: 0,
        qualityPacketCount: 8,
      ),
      ComparisonTrialSummary(
        actionId: 'hammer',
        actionName: 'Hammer Curl',
        repCount: 5,
        medianRepMean: secondValue,
        medianRepP95: secondValue * 1.2,
        missingSamples: 0,
        maximumClipRatio: 0,
        qualityPacketCount: 5,
      ),
    ],
  );
}

class _FixedHistoryController extends ComparisonHistoryController {
  _FixedHistoryController(this.records);

  final List<ComparisonHistoryRecord> records;

  @override
  ComparisonHistoryState build() {
    return ComparisonHistoryState(records: records, isLoading: false);
  }
}
