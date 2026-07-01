import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/app/app.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/domain/repositories/training_history_repository.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';
import 'package:myemg/features/training/presentation/widgets/action_ranking_card.dart';
import 'package:myemg/features/training/presentation/widgets/activation_panel.dart';
import 'package:myemg/features/training/presentation/widgets/bilateral_performance_panel.dart';
import 'package:myemg/features/training/presentation/widgets/emg_recalibration_dialog.dart';
import 'package:myemg/features/training/presentation/widgets/exercise_selector.dart';
import 'package:myemg/features/training/presentation/widgets/live_summary_card.dart';
import 'package:myemg/features/training/presentation/widgets/session_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const phoneSizes = [Size(360, 800), Size(390, 844), Size(430, 932)];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('migrates legacy sessions and exercises to Biceps', () async {
    final legacySession = SessionSummary.fromJson({
      'exerciseName': 'Legacy Curl',
      'durationSeconds': 30,
      'repetitions': 8,
      'leftAverage': 64.5,
      'rightAverage': 0,
      'leftPeak': 82,
      'rightPeak': 0,
      'balanceScore': 0,
    });
    final repository = _MemoryTrainingHistoryRepository(
      [legacySession],
      exercises: const ['Legacy Curl', 'Cable Curl'],
    );
    final container = ProviderContainer(
      overrides: [
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(trainingControllerProvider);
    expect(legacySession.targetMuscle, 'Biceps');
    expect(state.selectedTargetMuscle, 'Biceps');
    expect(
      state.exercisesByMuscle['Biceps'],
      containsAll(['Legacy Curl', 'Cable Curl']),
    );
    expect(
      repository.savedExercisesByMuscle?['Biceps'],
      contains('Legacy Curl'),
    );
  });

  test(
    'restores last selected muscle and falls back from an invalid one',
    () async {
      Future<String> loadSelected(String selectedMuscle) async {
        final repository = _MemoryTrainingHistoryRepository(
          const [],
          targetMuscles: const ['Biceps', 'Triceps', 'Legs'],
          exercisesByMuscle: const {
            'Biceps': ['Bicep Curl'],
            'Triceps': ['Triceps Pushdown'],
            'Legs': ['Squat'],
          },
          selectedTargetMuscle: selectedMuscle,
        );
        final container = ProviderContainer(
          overrides: [
            trainingHistoryRepositoryProvider.overrideWithValue(repository),
          ],
        );
        container.read(trainingControllerProvider);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        final selected = container
            .read(trainingControllerProvider)
            .selectedTargetMuscle;
        container.dispose();
        return selected;
      }

      expect(await loadSelected('Triceps'), 'Triceps');
      expect(await loadSelected('Unknown'), 'Biceps');
    },
  );

  test('isolates rankings for muscles with the same exercise name', () {
    const state = TrainingState(
      selectedTargetMuscle: 'Biceps',
      actionRankings: [
        SessionSummary(
          targetMuscle: 'Biceps',
          exerciseName: 'Press',
          durationSeconds: 30,
          repetitions: 8,
          leftAverage: 60,
          rightAverage: 0,
          leftPeak: 80,
          rightPeak: 0,
          balanceScore: 0,
        ),
        SessionSummary(
          targetMuscle: 'Triceps',
          exerciseName: 'Press',
          durationSeconds: 30,
          repetitions: 10,
          leftAverage: 90,
          rightAverage: 0,
          leftPeak: 98,
          rightPeak: 0,
          balanceScore: 0,
        ),
      ],
    );

    expect(state.sortedActionRankings, hasLength(1));
    expect(state.sortedActionRankings.single.targetMuscle, 'Biceps');
    expect(state.sortedActionRankings.single.leftAverage, 60);
  });

  test('clear, rename and delete only affect the selected muscle', () async {
    const bicepsSet = SessionSummary(
      targetMuscle: 'Biceps',
      exerciseName: 'Press',
      durationSeconds: 30,
      repetitions: 8,
      leftAverage: 60,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );
    const tricepsSet = SessionSummary(
      targetMuscle: 'Triceps',
      exerciseName: 'Press',
      durationSeconds: 30,
      repetitions: 10,
      leftAverage: 70,
      rightAverage: 0,
      leftPeak: 90,
      rightPeak: 0,
      balanceScore: 0,
    );
    final repository = _MemoryTrainingHistoryRepository(
      const [bicepsSet, tricepsSet],
      targetMuscles: const ['Biceps', 'Triceps', 'Legs'],
      exercisesByMuscle: const {
        'Biceps': ['Press', 'Curl'],
        'Triceps': ['Press'],
        'Legs': ['Squat'],
      },
      selectedTargetMuscle: 'Biceps',
    );
    final container = ProviderContainer(
      overrides: [
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(trainingControllerProvider.notifier);
    expect(
      await controller.renameExercise('Press', 'Chest Press'),
      ExerciseEditResult.success,
    );
    var state = container.read(trainingControllerProvider);
    expect(
      state.actionRankings
          .firstWhere((summary) => summary.targetMuscle == 'Biceps')
          .exerciseName,
      'Chest Press',
    );
    expect(
      state.actionRankings
          .firstWhere((summary) => summary.targetMuscle == 'Triceps')
          .exerciseName,
      'Press',
    );

    expect(
      await controller.deleteExercise('Chest Press'),
      ExerciseEditResult.success,
    );
    state = container.read(trainingControllerProvider);
    expect(state.exercises, ['Curl']);
    expect(state.selectedExercise, 'Curl');
    expect(
      state.actionRankings.where((summary) => summary.targetMuscle == 'Biceps'),
      isEmpty,
    );
    expect(
      state.actionRankings.where(
        (summary) => summary.targetMuscle == 'Triceps',
      ),
      [tricepsSet],
    );

    controller.selectTargetMuscle('Triceps');
    expect(await controller.clearActionRankings(), isTrue);
    expect(container.read(trainingControllerProvider).actionRankings, isEmpty);
  });

  test('clearing Biceps preserves Triceps sessions', () async {
    const bicepsSet = SessionSummary(
      targetMuscle: 'Biceps',
      exerciseName: 'Curl',
      durationSeconds: 30,
      repetitions: 8,
      leftAverage: 60,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );
    const tricepsSet = SessionSummary(
      targetMuscle: 'Triceps',
      exerciseName: 'Pushdown',
      durationSeconds: 30,
      repetitions: 8,
      leftAverage: 70,
      rightAverage: 0,
      leftPeak: 90,
      rightPeak: 0,
      balanceScore: 0,
    );
    final repository = _MemoryTrainingHistoryRepository(
      const [bicepsSet, tricepsSet],
      targetMuscles: const ['Biceps', 'Triceps', 'Legs'],
      exercisesByMuscle: const {
        'Biceps': ['Curl'],
        'Triceps': ['Pushdown'],
        'Legs': ['Squat'],
      },
      selectedTargetMuscle: 'Biceps',
    );
    final container = ProviderContainer(
      overrides: [
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      await container
          .read(trainingControllerProvider.notifier)
          .clearActionRankings(),
      isTrue,
    );
    expect(container.read(trainingControllerProvider).actionRankings, [
      tricepsSet,
    ]);
    expect(repository.savedSessions, [tricepsSet]);
  });

  test('deleting the only selected exercise leaves a null selection', () async {
    final repository = _MemoryTrainingHistoryRepository(
      const [],
      targetMuscles: const ['Biceps', 'Shoulders'],
      exercisesByMuscle: const {
        'Biceps': ['Bicep Curl'],
        'Shoulders': ['Lateral Raise'],
      },
      selectedTargetMuscle: 'Shoulders',
    );
    final container = ProviderContainer(
      overrides: [
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final result = await container
        .read(trainingControllerProvider.notifier)
        .deleteExercise('Lateral Raise');

    expect(result, ExerciseEditResult.success);
    expect(container.read(trainingControllerProvider).exercises, isEmpty);
    expect(container.read(trainingControllerProvider).selectedExercise, isNull);
  });

  test('renaming a muscle updates its exercises and saved sessions', () async {
    const savedSet = SessionSummary(
      targetMuscle: 'Biceps',
      exerciseName: 'Bicep Curl',
      durationSeconds: 30,
      repetitions: 8,
      leftAverage: 70,
      rightAverage: 0,
      leftPeak: 90,
      rightPeak: 0,
      balanceScore: 0,
    );
    final repository = _MemoryTrainingHistoryRepository(
      const [savedSet],
      targetMuscles: const ['Biceps', 'Triceps'],
      exercisesByMuscle: const {
        'Biceps': ['Bicep Curl'],
        'Triceps': ['Pushdown'],
      },
      selectedTargetMuscle: 'Biceps',
    );
    final container = ProviderContainer(
      overrides: [
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final result = await container
        .read(trainingControllerProvider.notifier)
        .renameTargetMuscle('Biceps', 'Arms');
    final state = container.read(trainingControllerProvider);

    expect(result, ExerciseEditResult.success);
    expect(state.targetMuscles, ['Arms', 'Triceps']);
    expect(state.selectedTargetMuscle, 'Arms');
    expect(state.exercisesByMuscle['Arms'], ['Bicep Curl']);
    expect(state.exercisesByMuscle.containsKey('Biceps'), isFalse);
    expect(state.actionRankings.single.targetMuscle, 'Arms');
    expect(repository.savedSessions.single.targetMuscle, 'Arms');
    expect(repository.savedSelectedTargetMuscle, 'Arms');
  });

  test('deleting the final muscle recreates an empty-history Biceps', () async {
    const savedSet = SessionSummary(
      targetMuscle: 'Shoulders',
      exerciseName: 'Lateral Raise',
      durationSeconds: 30,
      repetitions: 8,
      leftAverage: 70,
      rightAverage: 0,
      leftPeak: 90,
      rightPeak: 0,
      balanceScore: 0,
    );
    final repository = _MemoryTrainingHistoryRepository(
      const [savedSet],
      targetMuscles: const ['Shoulders'],
      exercisesByMuscle: const {
        'Shoulders': ['Lateral Raise'],
      },
      selectedTargetMuscle: 'Shoulders',
    );
    final container = ProviderContainer(
      overrides: [
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final result = await container
        .read(trainingControllerProvider.notifier)
        .deleteTargetMuscle('Shoulders');
    final state = container.read(trainingControllerProvider);

    expect(result, ExerciseEditResult.success);
    expect(state.targetMuscles, ['Biceps']);
    expect(state.selectedTargetMuscle, 'Biceps');
    expect(state.exercises, ['Bicep Curl', 'Hammer Curl']);
    expect(state.selectedExercise, 'Bicep Curl');
    expect(state.actionRankings, isEmpty);
    expect(repository.savedSessions, isEmpty);
  });

  test(
    'parses firmware invalid flag and defaults legacy payloads to valid',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        deviceConnectionControllerProvider.notifier,
      );

      final invalidJson = controller.parseEmgPayloadForTesting(
        utf8.encode('{"act":88.5,"raw":4095,"env":42.3,"invalid":1}'),
      );
      final validJson = controller.parseEmgPayloadForTesting(
        utf8.encode('{"act":23.5,"raw":2048,"env":42.3,"invalid":0}'),
      );
      final legacySingle = controller.parseEmgPayloadForTesting(
        utf8.encode('23.5'),
      );
      final legacyPair = controller.parseEmgPayloadForTesting(
        utf8.encode('23.5,87'),
      );
      final invalidBoolean = controller.parseEmgPayloadForTesting(
        utf8.encode('{"act":88.5,"raw":4095,"env":42.3,"invalid":true}'),
      );
      final truncatedJson = controller.parseEmgPayloadForTesting(
        utf8.encode('{"act":23.5,"raw":2048,'),
      );
      final emptyPayload = controller.parseEmgPayloadForTesting(const []);
      final randomText = controller.parseEmgPayloadForTesting(
        utf8.encode('not emg data'),
      );

      expect(invalidJson?.invalid, isTrue);
      expect(invalidJson?.smoothEmg, 88.5);
      expect(invalidJson?.rawEmg, 4095);
      expect(validJson?.invalid, isFalse);
      expect(invalidBoolean?.invalid, isTrue);
      expect(legacySingle?.invalid, isFalse);
      expect(legacySingle?.smoothEmg, 23.5);
      expect(legacyPair?.invalid, isFalse);
      expect(legacyPair?.smoothEmg, 23.5);
      expect(truncatedJson, isNull);
      expect(emptyPayload, isNull);
      expect(randomText, isNull);

      controller.handleEmgValueForTesting(
        DeviceSide.left,
        utf8.encode('{"act":23.5,"raw":2048,"env":42.3,"invalid":0}'),
      );
      final beforeDiscardedFrames = container
          .read(deviceConnectionControllerProvider)
          .leftDevice;
      controller.handleEmgValueForTesting(
        DeviceSide.left,
        utf8.encode('{"act":23.5,"raw":2048,'),
      );
      controller.handleEmgValueForTesting(DeviceSide.left, const []);
      controller.handleEmgValueForTesting(
        DeviceSide.left,
        utf8.encode('not emg data'),
      );
      final afterDiscardedFrames = container
          .read(deviceConnectionControllerProvider)
          .leftDevice;
      expect(afterDiscardedFrames.smoothEmg, beforeDiscardedFrames.smoothEmg);
      expect(afterDiscardedFrames.rawEmg, beforeDiscardedFrames.rawEmg);
      expect(
        afterDiscardedFrames.isInvalidSample,
        beforeDiscardedFrames.isInvalidSample,
      );
    },
  );

  test(
    'starting with an invalid device sample does not add a sample',
    () async {
      final container = ProviderContainer(
        overrides: [
          deviceConnectionControllerProvider.overrideWith(
            _SampleDeviceConnectionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(trainingControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final deviceController =
          container.read(deviceConnectionControllerProvider.notifier)
              as _SampleDeviceConnectionController;
      deviceController.emitInvalidSample();

      container.read(trainingControllerProvider.notifier).toggleSession();
      final state = container.read(trainingControllerProvider);

      expect(state.isRunning, isTrue);
      expect(state.sampleCount, 0);
      expect(state.leftAverage, 0);
      expect(state.leftPeak, 0);
      expect(state.repetitions, 0);
      expect(state.rawSamples, isEmpty);
    },
  );

  test(
    'invalid samples do not update live values or training metrics',
    () async {
      final container = ProviderContainer(
        overrides: [
          deviceConnectionControllerProvider.overrideWith(
            _SampleDeviceConnectionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(trainingControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final deviceController =
          container.read(deviceConnectionControllerProvider.notifier)
              as _SampleDeviceConnectionController;
      final trainingController = container.read(
        trainingControllerProvider.notifier,
      );

      deviceController.emitValidSample(raw: 1200, activation: 40);
      expect(container.read(trainingControllerProvider).leftActivation, 40);
      expect(
        container.read(trainingControllerProvider).rawEmgSamples,
        hasLength(1),
      );

      trainingController.toggleSession();
      final beforeInvalid = container.read(trainingControllerProvider);

      deviceController.emitInvalidSample();
      final afterInvalid = container.read(trainingControllerProvider);
      expect(
        container
            .read(deviceConnectionControllerProvider)
            .leftDevice
            .isInvalidSample,
        isTrue,
      );
      expect(afterInvalid.leftActivation, beforeInvalid.leftActivation);
      expect(afterInvalid.sampleCount, beforeInvalid.sampleCount);
      expect(afterInvalid.leftAverage, beforeInvalid.leftAverage);
      expect(afterInvalid.leftPeak, beforeInvalid.leftPeak);
      expect(afterInvalid.repetitions, beforeInvalid.repetitions);
      expect(afterInvalid.rawEmgSamples, beforeInvalid.rawEmgSamples);

      deviceController.emitValidSample(raw: 1300, activation: 55);
      final afterValid = container.read(trainingControllerProvider);
      expect(afterValid.leftActivation, 55);
      expect(afterValid.sampleCount, beforeInvalid.sampleCount + 1);
      expect(afterValid.rawEmgSamples, hasLength(2));

      trainingController.toggleSession();
      deviceController.emitInvalidSample();
      final beforeResume = container.read(trainingControllerProvider);

      trainingController.toggleSession();
      final afterResume = container.read(trainingControllerProvider);
      expect(afterResume.isRunning, isTrue);
      expect(afterResume.sampleCount, beforeResume.sampleCount);
      expect(afterResume.leftAverage, beforeResume.leftAverage);
      expect(afterResume.leftPeak, beforeResume.leftPeak);
      expect(afterResume.repetitions, beforeResume.repetitions);
      expect(afterResume.rawSamples, beforeResume.rawSamples);
    },
  );

  testWidgets('shows and clears the signal unstable warning', (tester) async {
    Widget buildPanel({required bool signalUnstable}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BilateralPerformancePanel(
                state: const TrainingState(),
                leftConnected: true,
                signalUnstable: signalUnstable,
                onRecalibrate: () {},
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildPanel(signalUnstable: true));
    expect(find.text('Signal unstable'), findsOneWidget);

    await tester.pumpWidget(buildPanel(signalUnstable: false));
    await tester.pump();
    expect(find.text('Signal unstable'), findsNothing);
  });

  test('does not save a session with fewer than five valid samples', () async {
    const historicalSet = SessionSummary(
      exerciseName: 'Hammer Curl',
      durationSeconds: 30,
      repetitions: 8,
      leftAverage: 60,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );
    final repository = _MemoryTrainingHistoryRepository(const [historicalSet]);
    final container = ProviderContainer(
      overrides: [
        deviceConnectionControllerProvider.overrideWith(
          _SampleDeviceConnectionController.new,
        ),
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final deviceController =
        container.read(deviceConnectionControllerProvider.notifier)
            as _SampleDeviceConnectionController;
    final trainingController = container.read(
      trainingControllerProvider.notifier,
    );

    deviceController.emitValidSample(raw: 1200, activation: 40);
    trainingController.toggleSession();
    for (var index = 0; index < 3; index++) {
      deviceController.emitValidSample(
        raw: 1201 + index.toDouble(),
        activation: 41 + index.toDouble(),
      );
    }

    final result = await trainingController.endSession();

    expect(result, EndSessionResult.notEnoughValidData);
    expect(container.read(trainingControllerProvider).actionRankings, [
      historicalSet,
    ]);
    expect(container.read(trainingControllerProvider).hasSessionData, isFalse);
    expect(repository.savedSessions, [historicalSet]);
  });

  test('saves a session with at least five valid samples', () async {
    final repository = _MemoryTrainingHistoryRepository(const []);
    final container = ProviderContainer(
      overrides: [
        deviceConnectionControllerProvider.overrideWith(
          _SampleDeviceConnectionController.new,
        ),
        trainingHistoryRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(trainingControllerProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final deviceController =
        container.read(deviceConnectionControllerProvider.notifier)
            as _SampleDeviceConnectionController;
    final trainingController = container.read(
      trainingControllerProvider.notifier,
    );

    deviceController.emitValidSample(raw: 1200, activation: 40);
    trainingController.toggleSession();
    for (var index = 0; index < 4; index++) {
      deviceController.emitValidSample(
        raw: 1201 + index.toDouble(),
        activation: 41 + index.toDouble(),
      );
    }

    final result = await trainingController.endSession();

    expect(result, EndSessionResult.saved);
    expect(
      container.read(trainingControllerProvider).actionRankings,
      hasLength(1),
    );
    expect(repository.savedSessions, hasLength(1));
    expect(repository.savedSessions.single.targetMuscle, 'Biceps');
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
      expect(find.text('Biceps'), findsWidgets);
      expect(find.text('No EMG connected'), findsWidgets);
      expect(find.textContaining('bilateral'), findsNothing);
      expect(find.text('Start Session'), findsOneWidget);
      expect(find.text('Recalibrate EMG'), findsOneWidget);
      expect(find.byType(LiveSummaryCard), findsNothing);
      expect(
        find.descendant(
          of: find.byType(BilateralPerformancePanel),
          matching: find.byKey(const ValueKey('biceps-live-summary')),
        ),
        findsOneWidget,
      );
      expect(find.byType(CompactLiveSummarySection), findsOneWidget);

      final activationPanel = tester.getRect(
        find.byKey(const ValueKey('biceps-activation-panel')),
      );
      final liveSummary = tester.getRect(
        find.byKey(const ValueKey('biceps-live-summary')),
      );
      expect(activationPanel.right, lessThanOrEqualTo(liveSummary.left));
      expect(activationPanel.top, liveSummary.top);
      expect(activationPanel.height, lessThanOrEqualTo(244));

      final rankingCard = find.byKey(const ValueKey('action-ranking-card'));
      expect(rankingCard, findsOneWidget);
      expect(tester.getTopLeft(rankingCard).dy, lessThan(size.height));
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

    expect(
      find.descendant(
        of: find.byType(SessionControls),
        matching: find.text('Recalibrate EMG'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(BilateralPerformancePanel),
        matching: find.byKey(const ValueKey('recalibrate-emg-button')),
      ),
      findsOneWidget,
    );

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
          home: Scaffold(
            body: SizedBox(height: 104, child: ExerciseSelector()),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('muscle-selector')), findsOneWidget);
    expect(find.text('Bicep Curl'), findsNothing);

    await tester.tap(find.text('Biceps').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('muscle-selector')), findsNothing);
    expect(
      find.byKey(const ValueKey('back-to-muscles-button')),
      findsOneWidget,
    );
    expect(find.text('Bicep Curl'), findsOneWidget);
    expect(find.text('Hammer Curl'), findsOneWidget);

    await tester.tap(find.byTooltip('Add exercise'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Squat');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Squat'), findsOneWidget);

    await tester.longPress(find.text('Squat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Front Squat');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Front Squat'), findsOneWidget);
    expect(find.text('Squat'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('back-to-muscles-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('muscle-selector')), findsOneWidget);
    expect(find.text('Bicep Curl'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('long pressing a muscle opens rename and delete actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ExerciseSelector())),
      ),
    );

    await tester.longPress(find.text('Biceps').first);
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('adding a muscle enters its empty exercise selector', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ExerciseSelector())),
      ),
    );

    await tester.tap(find.byTooltip('Add target muscle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Shoulders');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('back-to-muscles-button')),
      findsOneWidget,
    );
    expect(find.text('Shoulders'), findsOneWidget);
    expect(find.text('No exercises yet'), findsOneWidget);
    expect(find.byTooltip('Add exercise'), findsOneWidget);
  });

  testWidgets('switches muscle exercises and dynamic training copy', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MemoryTrainingHistoryRepository(
      const [],
      targetMuscles: const ['Biceps', 'Triceps', 'Legs'],
      exercisesByMuscle: const {
        'Biceps': ['Bicep Curl'],
        'Triceps': ['Triceps Pushdown', 'Overhead Extension'],
        'Legs': ['Squat'],
      },
      selectedTargetMuscle: 'Triceps',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MyEmgApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Live triceps activation'), findsOneWidget);
    expect(find.text('Triceps Activation'), findsOneWidget);
    expect(find.text('Triceps Pushdown'), findsNothing);
    await tester.tap(find.text('Triceps').first);
    await tester.pumpAndSettle();
    expect(find.text('Triceps Pushdown'), findsOneWidget);

    final tricepsExerciseList = find.descendant(
      of: find.byKey(const ValueKey('exercise-selector-Triceps')),
      matching: find.byType(ListView),
    );
    await tester.drag(tricepsExerciseList, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.text('Overhead Extension'), findsOneWidget);
    expect(find.text('Best Exercises for Triceps'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('back-to-muscles-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Legs').first);
    await tester.pumpAndSettle();

    expect(find.text('Live leg muscle activation'), findsOneWidget);
    expect(find.text('Legs Activation'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    expect(repository.savedSelectedTargetMuscle, 'Legs');
  });

  testWidgets('blocks starting when the selected muscle has no exercise', (
    tester,
  ) async {
    final repository = _MemoryTrainingHistoryRepository(
      const [],
      targetMuscles: const ['Biceps', 'Shoulders'],
      exercisesByMuscle: const {
        'Biceps': ['Bicep Curl'],
        'Shoulders': [],
      },
      selectedTargetMuscle: 'Shoulders',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trainingHistoryRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MyEmgApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Start Session'));
    await tester.pump();

    expect(
      find.text('Add an exercise for Shoulders before starting.'),
      findsOneWidget,
    );
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

  test('uses peak activation to break equal-average ranking ties', () {
    const state = TrainingState(
      actionRankings: [
        SessionSummary(
          exerciseName: 'Lower Peak',
          durationSeconds: 30,
          repetitions: 4,
          leftAverage: 70,
          rightAverage: 0,
          leftPeak: 80,
          rightPeak: 0,
          balanceScore: 0,
        ),
        SessionSummary(
          exerciseName: 'Higher Peak',
          durationSeconds: 30,
          repetitions: 4,
          leftAverage: 70,
          rightAverage: 0,
          leftPeak: 92,
          rightPeak: 0,
          balanceScore: 0,
        ),
      ],
    );

    expect(state.sortedActionRankings.map((summary) => summary.exerciseName), [
      'Higher Peak',
      'Lower Peak',
    ]);
  });

  test('uses full average precision before peak activation', () {
    const state = TrainingState(
      actionRankings: [
        SessionSummary(
          exerciseName: 'Higher Precise Average',
          durationSeconds: 30,
          repetitions: 4,
          leftAverage: 72.4,
          rightAverage: 0,
          leftPeak: 80,
          rightPeak: 0,
          balanceScore: 0,
        ),
        SessionSummary(
          exerciseName: 'Higher Peak',
          durationSeconds: 30,
          repetitions: 4,
          leftAverage: 72.1,
          rightAverage: 0,
          leftPeak: 99,
          rightPeak: 0,
          balanceScore: 0,
        ),
      ],
    );

    expect(state.sortedActionRankings.map((summary) => summary.exerciseName), [
      'Higher Precise Average',
      'Higher Peak',
    ]);
    expect(state.sortedActionRankings.first.averageActivation, 72);
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

  test('recalculates the best set after deleting the previous best', () {
    const lowerSet = SessionSummary(
      exerciseName: 'Curl',
      durationSeconds: 30,
      repetitions: 4,
      leftAverage: 62,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );
    const bestSet = SessionSummary(
      exerciseName: 'Curl',
      durationSeconds: 42,
      repetitions: 12,
      leftAverage: 72,
      rightAverage: 0,
      leftPeak: 91,
      rightPeak: 0,
      balanceScore: 0,
    );
    const state = TrainingState(actionRankings: [lowerSet, bestSet]);

    final afterDeletion = state.copyWith(actionRankings: const [lowerSet]);

    expect(state.sortedActionRankings.single, same(bestSet));
    expect(afterDeletion.sortedActionRankings.single, same(lowerSet));
  });

  test(
    'deleting one set updates controller state and local sessions',
    () async {
      const firstSet = SessionSummary(
        exerciseName: 'Curl',
        durationSeconds: 30,
        repetitions: 8,
        leftAverage: 62,
        rightAverage: 0,
        leftPeak: 80,
        rightPeak: 0,
        balanceScore: 0,
      );
      const secondSet = SessionSummary(
        exerciseName: 'Curl',
        durationSeconds: 42,
        repetitions: 12,
        leftAverage: 72,
        rightAverage: 0,
        leftPeak: 91,
        rightPeak: 0,
        balanceScore: 0,
      );
      final repository = _MemoryTrainingHistoryRepository([
        firstSet,
        secondSet,
      ]);
      final container = ProviderContainer(
        overrides: [
          trainingHistoryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(trainingControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final target = container
          .read(trainingControllerProvider)
          .actionRankings[1];
      await container
          .read(trainingControllerProvider.notifier)
          .deleteSavedSession(target);

      expect(container.read(trainingControllerProvider).actionRankings, [
        firstSet,
      ]);
      expect(repository.savedSessions, [firstSet]);
    },
  );

  test(
    'saved-session mutations keep memory unchanged on storage failure',
    () async {
      const savedSet = SessionSummary(
        exerciseName: 'Bicep Curl',
        durationSeconds: 30,
        repetitions: 8,
        leftAverage: 62,
        rightAverage: 0,
        leftPeak: 80,
        rightPeak: 0,
        balanceScore: 0,
      );
      final repository = _MemoryTrainingHistoryRepository(
        const [savedSet],
        exercises: const ['Bicep Curl', 'Hammer Curl'],
      );
      final container = ProviderContainer(
        overrides: [
          trainingHistoryRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.read(trainingControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final controller = container.read(trainingControllerProvider.notifier);
      final originalState = container.read(trainingControllerProvider);

      repository.failSaveSessions = true;
      expect(await controller.deleteSavedSession(savedSet), isFalse);
      expect(
        container.read(trainingControllerProvider).actionRankings,
        originalState.actionRankings,
      );

      repository.failSaveSessions = false;
      repository.failClearSessions = true;
      expect(await controller.clearActionRankings(), isFalse);
      expect(
        container.read(trainingControllerProvider).actionRankings,
        originalState.actionRankings,
      );

      repository.failClearSessions = false;
      repository.failSaveSessions = true;
      expect(
        await controller.renameExercise('Bicep Curl', 'Cable Curl'),
        ExerciseEditResult.storageFailure,
      );
      expect(
        container.read(trainingControllerProvider).exercises,
        originalState.exercises,
      );
      expect(
        container
            .read(trainingControllerProvider)
            .actionRankings
            .single
            .exerciseName,
        'Bicep Curl',
      );
    },
  );

  testWidgets('shows expandable action ranking rows and deletes one set', (
    tester,
  ) async {
    var cleared = false;
    SessionSummary? deletedSession;
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const lowerCurlSet = SessionSummary(
      exerciseName: 'Bicep Curl',
      durationSeconds: 35,
      repetitions: 10,
      leftAverage: 62,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );
    const bestCurlSet = SessionSummary(
      exerciseName: 'Bicep Curl',
      durationSeconds: 42,
      repetitions: 12,
      leftAverage: 72,
      rightAverage: 0,
      leftPeak: 91,
      rightPeak: 0,
      balanceScore: 0,
    );
    const hammerSet = SessionSummary(
      exerciseName: 'Hammer Curl',
      durationSeconds: 40,
      repetitions: 11,
      leftAverage: 65,
      rightAverage: 0,
      leftPeak: 84,
      rightPeak: 0,
      balanceScore: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ActionRankingCard(
                onClearAll: () async {
                  cleared = true;
                  return true;
                },
                onDeleteSession: (summary) async {
                  deletedSession = summary;
                  return true;
                },
                rankings: const [bestCurlSet, hammerSet],
                sessions: const [lowerCurlSet, bestCurlSet, hammerSet],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Best Exercises for Biceps'), findsOneWidget);
    expect(find.text('Ranked by average biceps activation.'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);
    expect(find.text('Bicep Curl'), findsOneWidget);
    expect(find.text('Hammer Curl'), findsOneWidget);
    expect(find.text('Avg'), findsNWidgets(2));
    expect(find.text('Avg. Activation'), findsNothing);
    expect(find.text('72%'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
    expect(find.text('Set 1'), findsNothing);

    final card = tester.widget<Container>(
      find.byKey(const ValueKey('action-ranking-card')),
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFE978));
    expect((decoration.borderRadius! as BorderRadius).topLeft.x, 28);

    final clearAll = tester.widget<TextButton>(
      find.byKey(const ValueKey('clear-action-rankings-button')),
    );
    expect(
      clearAll.style!.backgroundColor!.resolve(<WidgetState>{}),
      const Color(0xFF111827),
    );
    expect(
      clearAll.style!.foregroundColor!.resolve(<WidgetState>{}),
      Colors.white,
    );

    await tester.tap(
      find.byKey(const ValueKey('clear-action-rankings-button')),
    );
    expect(cleared, isTrue);

    await tester.tap(find.byKey(const ValueKey('ranking-row-Bicep Curl')));
    await tester.pump();

    expect(find.text('Set 1'), findsOneWidget);
    expect(find.text('Set 2'), findsOneWidget);
    expect(find.text('0:35'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete set').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete this set?'), findsOneWidget);
    expect(find.text('This action cannot be undone.'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deletedSession, same(lowerCurlSet));

    await tester.tap(
      find.byKey(const ValueKey('clear-action-rankings-button')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ranking-details-Bicep Curl')),
      findsNothing,
    );
  });

  testWidgets('deleting the last set clears the expanded exercise', (
    tester,
  ) async {
    const onlySet = SessionSummary(
      exerciseName: 'Bicep Curl',
      durationSeconds: 35,
      repetitions: 10,
      leftAverage: 62,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionRankingCard(
            rankings: const [onlySet],
            sessions: const [onlySet],
            onClearAll: () async => true,
            onDeleteSession: (_) async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ranking-row-Bicep Curl')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ranking-details-Bicep Curl')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Delete set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ranking-details-Bicep Curl')),
      findsNothing,
    );
  });

  testWidgets('shows an error when deleting a set cannot be persisted', (
    tester,
  ) async {
    const savedSet = SessionSummary(
      exerciseName: 'Bicep Curl',
      durationSeconds: 35,
      repetitions: 10,
      leftAverage: 62,
      rightAverage: 0,
      leftPeak: 80,
      rightPeak: 0,
      balanceScore: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionRankingCard(
            rankings: const [savedSet],
            sessions: const [savedSet],
            onClearAll: () async => true,
            onDeleteSession: (_) async => false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('ranking-row-Bicep Curl')));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to update saved sessions.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ranking-details-Bicep Curl')),
      findsOneWidget,
    );
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

  testWidgets('renders compact live summary as a vertical metric list', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 130,
              height: 278,
              child: CompactLiveSummarySection(
                state: TrainingState(
                  leftActivation: 64,
                  leftAverage: 42.6,
                  leftPeak: 91,
                  elapsedSeconds: 125,
                  repetitions: 7,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('64%'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
    expect(find.text('43%'), findsOneWidget);
    expect(find.text('Peak'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('2:05'), findsOneWidget);
    expect(find.text('Reps'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
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

class _SampleDeviceConnectionController extends DeviceConnectionController {
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

  void emitValidSample({required double raw, required double activation}) {
    state = state.copyWith(
      leftDevice: state.leftDevice.copyWith(
        rawEmg: raw,
        smoothEmg: activation,
        isInvalidSample: false,
      ),
    );
  }

  void emitInvalidSample() {
    state = state.copyWith(
      leftDevice: state.leftDevice.copyWith(isInvalidSample: true),
    );
  }
}

class _MemoryTrainingHistoryRepository implements TrainingHistoryRepository {
  _MemoryTrainingHistoryRepository(
    this.sessions, {
    this.exercises = const [],
    this.targetMuscles = const [],
    this.exercisesByMuscle,
    this.selectedTargetMuscle,
  }) : savedSessions = [...sessions],
       savedExercises = [...exercises],
       savedTargetMuscles = [...targetMuscles],
       savedExercisesByMuscle = exercisesByMuscle?.map(
         (muscle, exercises) => MapEntry(muscle, [...exercises]),
       ),
       savedSelectedTargetMuscle = selectedTargetMuscle;

  final List<SessionSummary> sessions;
  final List<String> exercises;
  final List<String> targetMuscles;
  final Map<String, List<String>>? exercisesByMuscle;
  final String? selectedTargetMuscle;
  List<SessionSummary> savedSessions;
  List<String> savedExercises;
  List<String> savedTargetMuscles;
  Map<String, List<String>>? savedExercisesByMuscle;
  String? savedSelectedTargetMuscle;
  bool failClearSessions = false;
  bool failSaveSessions = false;
  bool failSaveExercises = false;

  @override
  Future<void> clearSessions() async {
    if (failClearSessions) throw StateError('clear failed');
    savedSessions = const [];
  }

  @override
  Future<List<String>> loadExercises() async => exercises;

  @override
  Future<Map<String, List<String>>?> loadExercisesByMuscle() async {
    return exercisesByMuscle?.map(
      (muscle, exercises) => MapEntry(muscle, [...exercises]),
    );
  }

  @override
  Future<String?> loadSelectedTargetMuscle() async => selectedTargetMuscle;

  @override
  Future<List<SessionSummary>> loadSessions() async => sessions;

  @override
  Future<List<String>> loadTargetMuscles() async => targetMuscles;

  @override
  Future<void> saveExercises(List<String> exercises) async {
    if (failSaveExercises) throw StateError('exercise save failed');
    savedExercises = [...exercises];
  }

  @override
  Future<void> saveExercisesByMuscle(
    Map<String, List<String>> exercisesByMuscle,
  ) async {
    if (failSaveExercises) throw StateError('exercise save failed');
    savedExercisesByMuscle = exercisesByMuscle.map(
      (muscle, exercises) => MapEntry(muscle, [...exercises]),
    );
  }

  @override
  Future<void> saveSession(SessionSummary summary) async {
    savedSessions = [summary, ...savedSessions];
  }

  @override
  Future<void> saveSessions(List<SessionSummary> summaries) async {
    if (failSaveSessions) throw StateError('session save failed');
    savedSessions = [...summaries];
  }

  @override
  Future<void> saveSelectedTargetMuscle(String muscle) async {
    savedSelectedTargetMuscle = muscle;
  }

  @override
  Future<void> saveTargetMuscles(List<String> muscles) async {
    savedTargetMuscles = [...muscles];
  }
}
