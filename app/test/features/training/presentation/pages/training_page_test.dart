import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/app/app.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/widgets/action_ranking_card.dart';
import 'package:myemg/features/training/presentation/widgets/activation_panel.dart';
import 'package:myemg/features/training/presentation/widgets/emg_recalibration_dialog.dart';
import 'package:myemg/features/training/presentation/widgets/exercise_selector.dart';
import 'package:myemg/features/training/presentation/widgets/live_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const phoneSizes = [Size(360, 800), Size(390, 844), Size(430, 932)];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
      expect(find.text('Live biceps activation'), findsOneWidget);
      expect(find.text('Biceps Activation'), findsOneWidget);
      expect(find.text('Biceps'), findsOneWidget);
      expect(find.text('No EMG connected'), findsWidgets);
      expect(find.textContaining('bilateral'), findsNothing);
      expect(find.text('Start Session'), findsOneWidget);
      expect(find.text('Recalibrate EMG'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    });
  }

  testWidgets('uses two-tab navigation and opens the device page', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyEmgApp()));

    expect(find.text('Training'), findsWidgets);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.text('History'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pumpAndSettle();

    expect(find.text('EMG Device'), findsOneWidget);
    expect(find.text('My_EMG'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Left Device'), findsNothing);
    expect(find.text('Right Device'), findsNothing);
    expect(find.textContaining('DEBUG'), findsNothing);
  });

  testWidgets('asks for a connection before starting a session', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyEmgApp()));

    await tester.tap(find.text('Start Session'));
    await tester.pump();

    expect(
      find.text('Connect My_EMG before starting a session.'),
      findsOneWidget,
    );
  });

  testWidgets('starts training only after session calibration completes', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConnectionControllerProvider.overrideWith(
            _ConnectedDeviceConnectionController.new,
          ),
        ],
        child: const MyEmgApp(),
      ),
    );

    await tester.tap(find.text('Start Session'));
    await tester.pumpAndSettle();

    expect(find.text('Prepare Session'), findsOneWidget);
    expect(find.text('Start Calibration'), findsOneWidget);
    expect(find.text('Pause Session'), findsNothing);

    await tester.tap(find.text('Start Calibration'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Get ready'), findsOneWidget);
    expect(find.text('Pause Session'), findsNothing);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.text('Calibration complete'), findsOneWidget);
    expect(find.text('Pause Session'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Pause Session'), findsOneWidget);
    expect(find.text('Prepare Session'), findsNothing);
  });

  testWidgets('shows a failure when recalibrating without a connection', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MyEmgApp()));

    await tester.tap(find.text('Recalibrate EMG'));
    await tester.pumpAndSettle();

    expect(find.text('Start Recalibration'), findsOneWidget);
    await tester.tap(find.text('Start Recalibration'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Failed to send recalibration command. Please reconnect My_EMG.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows every successful recalibration stage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => showEmgRecalibrationGuideDialog(
                context: context,
                onStartRecalibration: () async => true,
              ),
              child: const Text('Open guide'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open guide'));
    await tester.pumpAndSettle();
    expect(find.text('Recalibrate EMG'), findsOneWidget);

    await tester.tap(find.text('Start Recalibration'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Get ready'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('recalibration-countdown-warmup')),
          )
          .data,
      '2',
    );

    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.text('Relax'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('recalibration-countdown-relax')),
          )
          .data,
      '3',
    );

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.text('Max contraction'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('recalibration-countdown-maxContraction'),
            ),
          )
          .data,
      '5',
    );

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }
    expect(find.text('Calibration complete'), findsOneWidget);
    expect(find.text('You can start training now.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

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
    expect(decoded.averageActivation, 73);
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
    expect(state.sortedActionRankings.single.averageActivation, 80);
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
    expect(find.text('80%'), findsOneWidget);
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
                  LiveSummaryCard(state: TrainingState()),
                  SizedBox(height: 12),
                  LiveSummaryCard(
                    state: TrainingState(
                      leftActivation: 100,
                      leftAverage: 100,
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

    expect(find.text('100%'), findsWidgets);
    expect(find.textContaining('L '), findsNothing);
    expect(find.textContaining('R '), findsNothing);
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
              child: ActivationPanel(
                side: 'Biceps',
                value: 100,
                peak: 100,
                average: 100,
                color: AppColors.orange,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Biceps'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });
}

class _ConnectedDeviceConnectionController extends DeviceConnectionController {
  @override
  DeviceConnectionState build() {
    return const DeviceConnectionState(
      leftDevice: EmgDeviceConnection(
        side: DeviceSide.left,
        displayName: 'My_EMG',
        connected: true,
      ),
      rightDevice: EmgDeviceConnection(
        side: DeviceSide.right,
        displayName: 'Unused',
      ),
    );
  }

  @override
  Future<bool> sendRecalibrateCommand() async => true;
}
