import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/app/app.dart';
import 'package:myemg/features/comparison/data/repositories/local_exercise_catalog_repository.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_controller.dart';
import 'package:myemg/features/comparison/presentation/pages/comparison_page.dart';
import 'package:myemg/features/devices/domain/entities/emg_packet.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('disconnected device directs the user to Devices', (
    tester,
  ) async {
    var openedDevices = false;
    await _pumpComparison(
      tester,
      device: _device(connected: false),
      onOpenDevices: () => openedDevices = true,
    );

    expect(
      find.byKey(const ValueKey('comparison-device-disconnected')),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Devices'));
    expect(openedDevices, isTrue);
  });

  testWidgets('legacy firmware shows an update card and not Compare setup', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.legacy),
    );

    expect(
      find.byKey(const ValueKey('comparison-firmware-update-required')),
      findsOneWidget,
    );
    expect(find.text('Firmware update required'), findsOneWidget);
    expect(find.text('Set up this comparison'), findsNothing);
  });

  testWidgets('BLE v2 firmware enters Compare setup', (tester) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    expect(find.text('Set up this comparison'), findsNothing);
    expect(find.text('Select 2–4 actions'), findsOneWidget);
    expect(
      find.text('Keep the same sensor placement for every action.'),
      findsOneWidget,
    );
    expect(find.textContaining('MVC'), findsNothing);
  });

  testWidgets('Recent comparisons opens from the setup overflow menu', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    await tester.tap(find.byKey(const ValueKey('comparison-overflow-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent comparisons'));
    await tester.pumpAndSettle();

    expect(find.text('No completed comparisons yet.'), findsOneWidget);
    expect(find.textContaining('Legacy'), findsNothing);
  });

  testWidgets('empty catalog directs the user to Manage library', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalExerciseCatalogRepository.storageKey: jsonEncode(
        const UserExerciseCatalog().toJson(),
      ),
    });

    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    expect(find.textContaining('exercise library is empty'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('comparison-start-calibration')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a muscle with fewer than two actions cannot calibrate', (
    tester,
  ) async {
    const catalog = UserExerciseCatalog(
      muscles: [
        MuscleDefinition(id: UserExerciseCatalog.bicepsId, name: 'Biceps'),
      ],
      actions: [
        ActionDefinition(
          id: 'action-only',
          muscleId: UserExerciseCatalog.bicepsId,
          name: 'Only Action',
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      LocalExerciseCatalogRepository.storageKey: jsonEncode(catalog.toJson()),
    });

    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    expect(find.textContaining('Add at least 2 actions'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('comparison-start-calibration')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('fifth selected action is rejected with a SnackBar', (
    tester,
  ) async {
    final catalog = UserExerciseCatalog(
      muscles: const [
        MuscleDefinition(id: UserExerciseCatalog.bicepsId, name: 'Biceps'),
      ],
      actions: List.generate(
        5,
        (index) => ActionDefinition(
          id: 'action-$index',
          muscleId: UserExerciseCatalog.bicepsId,
          name: 'Action ${index + 1}',
        ),
      ),
    );
    SharedPreferences.setMockInitialValues({
      LocalExerciseCatalogRepository.storageKey: jsonEncode(catalog.toJson()),
    });
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byKey(ValueKey('select-action-action-$index')));
      await tester.pump();
    }

    expect(
      find.text('This comparison supports up to 4 actions.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('select-action-action-4')),
          )
          .selected,
      isFalse,
    );
  });

  testWidgets('Manage library opens from setup but not an active phase', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    await tester.tap(find.byKey(const ValueKey('manage-exercise-library')));
    await tester.pumpAndSettle();
    expect(find.text('Manage muscles'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
      comparisonState: const ComparisonState(
        phase: ComparisonPhase.recording,
        targetMuscle: 'Biceps',
        actions: _actions,
        baseline: 100,
        noise: 1,
      ),
    );
    expect(find.byKey(const ValueKey('manage-exercise-library')), findsNothing);
  });

  testWidgets('corrupt catalog shows defaults with a non-blocking notice', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      LocalExerciseCatalogRepository.storageKey: '{broken json',
    });

    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
    );

    expect(find.text('Bicep Curl'), findsOneWidget);
    expect(
      find.textContaining('Defaults are being used temporarily'),
      findsOneWidget,
    );
  });

  testWidgets('protocol timeout offers an explicit retry', (tester) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocolDetectionTimedOut: true),
    );

    expect(
      find.byKey(const ValueKey('comparison-protocol-timeout')),
      findsOneWidget,
    );
    expect(find.text('Retry identification'), findsOneWidget);
  });

  testWidgets('recording shows curve and feedback bar without a percentage', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
      comparisonState: const ComparisonState(
        phase: ComparisonPhase.recording,
        targetMuscle: 'Biceps',
        actions: _actions,
        baseline: 100,
        noise: 1,
      ),
    );

    expect(
      find.byKey(const ValueKey('comparison-activity-curve')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('comparison-live-activity-bar')),
      findsOneWidget,
    );
    expect(find.textContaining('not used for ranking'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const ValueKey('comparison-overflow-menu')),
          )
          .enabled,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results contain only this session and no Best Exercises', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
      comparisonState: ComparisonState(
        phase: ComparisonPhase.completed,
        targetMuscle: 'Biceps',
        actions: _actions,
        baseline: 100,
        noise: 1,
        completedTrials: [_trial(_actions[0], 30), _trial(_actions[1], 20)],
      ),
    );

    expect(find.byKey(const ValueKey('comparison-results')), findsOneWidget);
    expect(find.text('Bicep Curl'), findsOneWidget);
    expect(find.text('Hammer Curl'), findsOneWidget);
    expect(find.textContaining('only to this session'), findsOneWidget);
    expect(find.textContaining('Best Exercises'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Bicep Curl')).dy,
      lessThan(tester.getTopLeft(find.text('Hammer Curl')).dy),
    );
  });

  testWidgets('invalid action can only be discarded and retested', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
      comparisonState: ComparisonState(
        phase: ComparisonPhase.review,
        targetMuscle: 'Biceps',
        actions: _actions,
        baseline: 100,
        noise: 1,
        pendingTrial: _trial(
          _actions.first,
          30,
          invalidReason: 'packet_loss_detected',
        ),
      ),
    );

    expect(find.text('Action recording invalid'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('comparison-invalid-retest')),
      findsOneWidget,
    );
    expect(find.textContaining('Confirm'), findsNothing);
    expect(find.text('Correct count'), findsNothing);
  });

  testWidgets('correcting rep count updates review without a framework error', (
    tester,
  ) async {
    final reviewState = ComparisonState(
      phase: ComparisonPhase.review,
      targetMuscle: 'Biceps',
      actions: _actions,
      baseline: 100,
      noise: 1,
      pendingTrial: _trial(_actions.first, 30),
    );
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
      comparisonController: () => _SuccessfulCorrectionController(reviewState),
    );

    await tester.tap(find.text('Correct count'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('Re-segment'));
    await tester.pumpAndSettle();

    expect(find.text('Correct repetition count'), findsNothing);
    expect(find.text('Detected 3, expected 10'), findsOneWidget);
  });

  testWidgets('unsupported rep correction returns to review with a message', (
    tester,
  ) async {
    await _pumpComparison(
      tester,
      device: _device(connected: true, protocol: EmgProtocolVersion.v2),
      comparisonState: ComparisonState(
        phase: ComparisonPhase.review,
        targetMuscle: 'Biceps',
        actions: _actions,
        baseline: 100,
        noise: 1,
        pendingTrial: _trial(_actions.first, 30),
      ),
    );

    await tester.tap(find.text('Correct count'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('Re-segment'));
    await tester.pumpAndSettle();

    expect(find.text('Correct repetition count'), findsNothing);
    expect(find.byKey(const ValueKey('comparison-rep-review')), findsOneWidget);
    expect(
      find.text(
        'The signal does not contain enough reliable boundaries for that count.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('leaving Compare during recording aborts the session', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConnectionControllerProvider.overrideWith(
            () => _FixedDeviceController(
              _device(connected: true, protocol: EmgProtocolVersion.v2),
            ),
          ),
          comparisonControllerProvider.overrideWith(
            () => _FixedComparisonController(
              const ComparisonState(
                phase: ComparisonPhase.recording,
                targetMuscle: 'Biceps',
                actions: _actions,
                baseline: 100,
                noise: 1,
              ),
            ),
          ),
        ],
        child: const MyEmgApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Devices'));
    await tester.pump();
    await tester.tap(find.text('Compare'));
    await tester.pump();

    expect(find.byKey(const ValueKey('comparison-aborted')), findsOneWidget);
  });

  testWidgets('backgrounding during recording aborts the session', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConnectionControllerProvider.overrideWith(
            () => _FixedDeviceController(
              _device(connected: true, protocol: EmgProtocolVersion.v2),
            ),
          ),
          comparisonControllerProvider.overrideWith(
            () => _FixedComparisonController(
              const ComparisonState(
                phase: ComparisonPhase.recording,
                targetMuscle: 'Biceps',
                actions: _actions,
                baseline: 100,
                noise: 1,
              ),
            ),
          ),
        ],
        child: const MyEmgApp(),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byKey(const ValueKey('comparison-aborted')), findsOneWidget);
  });

  testWidgets('system back during recording aborts instead of leaving', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceConnectionControllerProvider.overrideWith(
            () => _FixedDeviceController(
              _device(connected: true, protocol: EmgProtocolVersion.v2),
            ),
          ),
          comparisonControllerProvider.overrideWith(
            () => _FixedComparisonController(
              const ComparisonState(
                phase: ComparisonPhase.recording,
                targetMuscle: 'Biceps',
                actions: _actions,
                baseline: 100,
                noise: 1,
              ),
            ),
          ),
        ],
        child: const MyEmgApp(),
      ),
    );
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byKey(const ValueKey('comparison-aborted')), findsOneWidget);
  });
}

Future<void> _pumpComparison(
  WidgetTester tester, {
  required EmgDeviceConnection device,
  VoidCallback? onOpenDevices,
  ComparisonState? comparisonState,
  ComparisonController Function()? comparisonController,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceConnectionControllerProvider.overrideWith(
          () => _FixedDeviceController(device),
        ),
        if (comparisonController != null)
          comparisonControllerProvider.overrideWith(comparisonController)
        else if (comparisonState != null)
          comparisonControllerProvider.overrideWith(
            () => _FixedComparisonController(comparisonState),
          ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ComparisonPage(onOpenDevices: onOpenDevices ?? () {}),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

EmgDeviceConnection _device({
  required bool connected,
  EmgProtocolVersion protocol = EmgProtocolVersion.unknown,
  bool protocolDetectionTimedOut = false,
}) {
  return EmgDeviceConnection(
    side: DeviceSide.left,
    displayName: 'My_EMG',
    connected: connected,
    protocolVersion: protocol,
    protocolDetectionTimedOut: protocolDetectionTimedOut,
  );
}

const _actions = [
  ComparisonActionPlan(
    id: 'curl',
    name: 'Bicep Curl',
    loadKg: 10,
    rir: 2,
    plannedReps: 10,
  ),
  ComparisonActionPlan(
    id: 'hammer',
    name: 'Hammer Curl',
    loadKg: 10,
    rir: 2,
    plannedReps: 10,
  ),
];

ActionTrial _trial(
  ComparisonActionPlan action,
  double mean, {
  String? invalidReason,
}) {
  return ActionTrial(
    action: action,
    samples: const [],
    reps: [
      RepEmgResult(
        startDeviceMs: 0,
        endDeviceMs: 1000,
        sampleCount: 50,
        meanAdjustedEnv: mean,
        p95AdjustedEnv: mean * 1.2,
      ),
    ],
    recordedAt: DateTime(2026, 7, 3),
    totalMissingSamples: 0,
    maximumClipRatio: 0,
    qualityPacketCount: invalidReason == null ? 1 : 0,
    invalidReason: invalidReason,
  );
}

class _FixedDeviceController extends DeviceConnectionController {
  _FixedDeviceController(this.device);

  final EmgDeviceConnection device;

  @override
  DeviceConnectionState build() {
    return DeviceConnectionState(
      leftDevice: device,
      rightDevice: const EmgDeviceConnection(
        side: DeviceSide.right,
        displayName: 'Unused',
      ),
    );
  }
}

class _FixedComparisonController extends ComparisonController {
  _FixedComparisonController(this.initialState);

  final ComparisonState initialState;

  @override
  ComparisonState build() => initialState;
}

class _SuccessfulCorrectionController extends _FixedComparisonController {
  _SuccessfulCorrectionController(super.initialState);

  @override
  bool correctRepCount(int requestedCount) {
    final trial = state.pendingTrial!;
    state = state.copyWith(
      pendingTrial: trial.copyWith(
        reps: List.filled(requestedCount, trial.reps.single),
        correctedRepCount: requestedCount,
      ),
      clearError: true,
    );
    return true;
  }
}
