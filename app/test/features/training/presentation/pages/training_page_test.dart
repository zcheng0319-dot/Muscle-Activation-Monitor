import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/app/app.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/widgets/action_ranking_card.dart';
import 'package:myemg/features/training/presentation/widgets/activation_panel.dart';
import 'package:myemg/features/training/presentation/widgets/exercise_selector.dart';
import 'package:myemg/features/training/presentation/widgets/live_summary_card.dart';

void main() {
  const phoneSizes = [Size(360, 800), Size(390, 844), Size(430, 932)];

  for (final size in phoneSizes) {
    testWidgets('shows the mobile training page at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: MyEmgApp()));

      expect(find.text('Training'), findsWidgets);
      expect(find.text('Bilateral Performance'), findsOneWidget);
      expect(find.text('Left Bicep'), findsOneWidget);
      expect(find.text('Right Bicep'), findsOneWidget);
      expect(find.text('Start Session'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
    });
  }

  testWidgets('adds and renames custom actions', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SizedBox(height: 80, child: ExerciseSelector())),
        ),
      ),
    );

    expect(find.text('Bicep Curl'), findsOneWidget);
    expect(find.text('Hammer Curl'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Squat');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Squat'), findsOneWidget);

    await tester.longPress(find.text('Squat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Front Squat');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Front Squat'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('sorts action rankings by average activation', () {
    const state = TrainingState(
      actionRankings: [
        SessionSummary(
          exerciseName: 'Low',
          durationSeconds: 30,
          repetitions: 4,
          leftAverage: 30,
          rightAverage: 40,
          leftPeak: 70,
          rightPeak: 75,
          balanceScore: 90,
        ),
        SessionSummary(
          exerciseName: 'High',
          durationSeconds: 30,
          repetitions: 6,
          leftAverage: 80,
          rightAverage: 70,
          leftPeak: 95,
          rightPeak: 90,
          balanceScore: 90,
        ),
      ],
    );

    expect(state.sortedActionRankings.map((summary) => summary.exerciseName), [
      'High',
      'Low',
    ]);
  });

  test('serializes session summaries to json', () {
    final createdAt = DateTime(2026, 6, 16, 16, 49);
    final summary = SessionSummary(
      exerciseName: 'Curl',
      durationSeconds: 45,
      repetitions: 8,
      leftAverage: 72.5,
      rightAverage: 70.5,
      leftPeak: 95,
      rightPeak: 92,
      balanceScore: 98,
      createdAt: createdAt,
    );

    final decoded = SessionSummary.fromJson(summary.toJson());

    expect(decoded.exerciseName, 'Curl');
    expect(decoded.averageActivation, 72);
    expect(decoded.peakActivation, 95);
    expect(decoded.createdAt, createdAt);
  });

  test('keeps the best action ranking per exercise', () {
    const state = TrainingState(
      actionRankings: [
        SessionSummary(
          exerciseName: 'Curl',
          durationSeconds: 30,
          repetitions: 4,
          leftAverage: 30,
          rightAverage: 40,
          leftPeak: 70,
          rightPeak: 75,
          balanceScore: 90,
        ),
        SessionSummary(
          exerciseName: 'Curl',
          durationSeconds: 45,
          repetitions: 6,
          leftAverage: 80,
          rightAverage: 70,
          leftPeak: 95,
          rightPeak: 90,
          balanceScore: 90,
        ),
      ],
    );

    expect(state.sortedActionRankings, hasLength(1));
    expect(state.sortedActionRankings.single.averageActivation, 75);
  });

  testWidgets('shows action ranking rows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionRankingCard(
            onClearAll: () {},
            rankings: const [
              SessionSummary(
                exerciseName: 'High',
                durationSeconds: 30,
                repetitions: 6,
                leftAverage: 80,
                rightAverage: 70,
                leftPeak: 95,
                rightPeak: 90,
                balanceScore: 90,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Action Ranking'), findsOneWidget);
    expect(find.text('Clear All'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
  });

  testWidgets('renders live summary at activation extremes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  LiveSummaryCard(
                    state: TrainingState(
                      leftActivation: 0,
                      rightActivation: 100,
                      leftAverage: 0,
                      rightAverage: 100,
                      rightPeak: 100,
                      sampleCount: 1,
                    ),
                  ),
                  SizedBox(height: 12),
                  LiveSummaryCard(
                    state: TrainingState(
                      leftActivation: 100,
                      rightActivation: 0,
                      leftAverage: 100,
                      rightAverage: 0,
                      leftPeak: 100,
                      sampleCount: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('R 100%'), findsOneWidget);
    expect(find.text('L 100%'), findsOneWidget);
    expect(find.text('Live Summary'), findsNWidgets(2));
  });

  testWidgets('renders activation columns at value extremes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 360,
              child: Row(
                children: [
                  Expanded(
                    child: ActivationPanel(
                      side: 'Left',
                      value: 0,
                      peak: 0,
                      average: 0,
                      color: AppColors.orange,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ActivationPanel(
                      side: 'Right',
                      value: 100,
                      peak: 100,
                      average: 100,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Left Bicep'), findsOneWidget);
    expect(find.text('Right Bicep'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });
}
