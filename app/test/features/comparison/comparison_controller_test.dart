import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';
import 'package:myemg/features/comparison/domain/repositories/comparison_history_repository.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_controller.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_history_controller.dart';
import 'package:myemg/features/devices/domain/entities/emg_packet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('configure accepts 2 to 4 actions and rejects counts outside it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    expect(
      controller.configure(targetMuscle: 'Biceps', actions: _plans(1)),
      isFalse,
    );
    expect(
      controller.configure(targetMuscle: 'Biceps', actions: _plans(2)),
      isTrue,
    );
    expect(
      controller.configure(targetMuscle: 'Biceps', actions: _plans(3)),
      isTrue,
    );
    expect(
      controller.configure(targetMuscle: 'Biceps', actions: _plans(4)),
      isTrue,
    );
    expect(
      controller.configure(targetMuscle: 'Biceps', actions: _plans(5)),
      isFalse,
    );
  });

  test('action order is editable before calibration and locked afterwards', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    expect(
      controller.configure(targetMuscle: 'Biceps', actions: _actions),
      isTrue,
    );
    expect(controller.reorderAction(0, 1), isTrue);
    expect(
      container.read(comparisonControllerProvider).actions.first.id,
      'hammer',
    );

    controller.beginCalibrationForTesting();
    expect(controller.reorderAction(0, 1), isFalse);
  });

  test('one calibration is reused across every action in the session', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);

    expect(controller.startCurrentAction(), isTrue);
    _emitReps(controller, amplitudes: [30, 30]);
    expect(controller.finishCurrentAction(), isTrue);
    expect(controller.acceptCurrentAction(), isTrue);

    var state = container.read(comparisonControllerProvider);
    expect(state.phase, ComparisonPhase.betweenActions);
    expect(state.currentActionIndex, 1);
    expect(state.baseline, 100);
    expect(state.noise, 1);

    expect(controller.startCurrentAction(), isTrue);
    _emitReps(controller, amplitudes: [24, 24]);
    expect(controller.finishCurrentAction(), isTrue);
    expect(controller.acceptCurrentAction(), isTrue);

    state = container.read(comparisonControllerProvider);
    expect(state.phase, ComparisonPhase.completed);
    expect(state.completedTrials, hasLength(2));
    expect(state.session?.isComplete, isTrue);
    expect(state.session?.baseline, 100);
  });

  test('completed sessions are saved and aborted sessions are not', () async {
    final history = _MemoryHistoryRepository();
    final container = ProviderContainer(
      overrides: [
        comparisonHistoryRepositoryProvider.overrideWithValue(history),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.startCurrentAction();
    _emitReps(controller, amplitudes: [30]);
    controller.finishCurrentAction();
    controller.acceptCurrentAction();
    controller.startCurrentAction();
    _emitReps(controller, amplitudes: [24]);
    controller.finishCurrentAction();
    controller.acceptCurrentAction();
    await Future<void>.delayed(Duration.zero);

    expect(history.records, hasLength(1));
    expect(history.records.single.targetMuscle, 'Biceps');

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.abort('test_abort');
    await Future<void>.delayed(Duration.zero);

    expect(history.records, hasLength(1));
  });

  test('rep correction rejects a count without enough signal boundaries', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.startCurrentAction();
    _emitReps(controller, amplitudes: [30, 30]);
    controller.finishCurrentAction();

    expect(controller.correctRepCount(5), isFalse);
    final state = container.read(comparisonControllerProvider);
    expect(state.pendingTrial?.repCount, 2);
    expect(state.errorMessage, 'requested_count_unavailable');
  });

  test('discard and retry keeps calibration and current action', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.startCurrentAction();
    _emitReps(controller, amplitudes: [30]);
    controller.finishCurrentAction();

    expect(controller.discardAndRetryCurrentAction(), isTrue);
    final state = container.read(comparisonControllerProvider);
    expect(state.phase, ComparisonPhase.ready);
    expect(state.currentActionIndex, 0);
    expect(state.baseline, 100);
    expect(state.pendingTrial, isNull);
  });

  test('device timestamp rollback aborts the active comparison', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.startCurrentAction();
    controller.handleSampleForTesting(
      const EmgSample(env: 130, deviceMs: 5, seq: 0, deviceRestarted: true),
    );

    final state = container.read(comparisonControllerProvider);
    expect(state.phase, ComparisonPhase.aborted);
    expect(state.errorMessage, 'device_restarted');
  });

  test(
    'metadata and transport quality are recorded but do not weight scores',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(comparisonControllerProvider.notifier);

      controller.configure(targetMuscle: 'Biceps', actions: _actions);
      _completeCalibration(controller);
      controller.startCurrentAction();
      controller.handleQualityForTesting(
        const EmgQuality(
          deviceMs: 1000,
          rawSamples: 500,
          nearRailSamples: 10,
          clipRatio: 0.02,
        ),
      );
      _emitReps(controller, amplitudes: [30], missingSamples: 3);
      controller.finishCurrentAction();

      final trial = container.read(comparisonControllerProvider).pendingTrial!;
      expect(trial.action.loadKg, 10);
      expect(trial.action.rir, 2);
      expect(trial.totalMissingSamples, 3);
      expect(trial.maximumClipRatio, 0.02);
      expect(trial.isValid, isFalse);
      expect(trial.invalidReason, 'packet_loss_detected');
      expect(controller.acceptCurrentAction(), isFalse);
      expect(trial.repCount, 1);
    },
  );

  test('severe clipping and missing quality packets invalidate an action', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.startCurrentAction();
    controller.handleQualityForTesting(
      const EmgQuality(
        deviceMs: 1000,
        rawSamples: 500,
        nearRailSamples: 40,
        clipRatio: 0.08,
      ),
    );
    _emitReps(controller, amplitudes: [30], includeQuality: false);
    controller.finishCurrentAction();

    var trial = container.read(comparisonControllerProvider).pendingTrial!;
    expect(trial.invalidReason, 'clipping_detected');
    expect(controller.acceptCurrentAction(), isFalse);
    expect(controller.discardAndRetryCurrentAction(), isTrue);

    controller.startCurrentAction();
    _emitReps(controller, amplitudes: [30], includeQuality: false);
    controller.finishCurrentAction();
    trial = container.read(comparisonControllerProvider).pendingTrial!;
    expect(trial.invalidReason, 'quality_unavailable');
    expect(controller.acceptCurrentAction(), isFalse);
  });

  test('minor clipping stays valid but is flagged', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    _completeCalibration(controller);
    controller.startCurrentAction();
    controller.handleQualityForTesting(
      const EmgQuality(
        deviceMs: 1000,
        rawSamples: 500,
        nearRailSamples: 5,
        clipRatio: 0.01,
      ),
    );
    _emitReps(controller, amplitudes: [30], includeQuality: false);
    controller.finishCurrentAction();

    final trial = container.read(comparisonControllerProvider).pendingTrial!;
    expect(trial.invalidReason, isNull);
    expect(trial.isValid, isTrue);
    expect(trial.hasMinorClipping, isTrue);
    expect(controller.acceptCurrentAction(), isTrue);
  });

  test('calibration timeout returns to setup and permits retry', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    controller.beginCalibrationForTesting();
    controller.triggerCalibrationTimeoutForTesting();

    final state = container.read(comparisonControllerProvider);
    expect(state.phase, ComparisonPhase.setup);
    expect(state.errorMessage, 'calibration_timeout');
  });

  test('calibration can be cancelled back to clean setup', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(comparisonControllerProvider.notifier);

    controller.configure(targetMuscle: 'Biceps', actions: _actions);
    controller.beginCalibrationForTesting();

    expect(controller.cancelCalibration(), isTrue);
    final state = container.read(comparisonControllerProvider);
    expect(state.phase, ComparisonPhase.setup);
    expect(state.baseline, isNull);
    expect(state.session, isNull);
  });
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

void _completeCalibration(ComparisonController controller) {
  controller.beginCalibrationForTesting();
  controller.handleCalibrationForTesting(
    const EmgCalibration(
      state: EmgCalibrationState.complete,
      baseline: 100,
      noise: 1,
      quality: 'good',
    ),
  );
}

void _emitReps(
  ComparisonController controller, {
  required List<double> amplitudes,
  int missingSamples = 0,
  bool includeQuality = true,
}) {
  if (includeQuality) {
    controller.handleQualityForTesting(
      const EmgQuality(
        deviceMs: 1000,
        rawSamples: 500,
        nearRailSamples: 0,
        clipRatio: 0,
      ),
    );
  }
  final values = <double>[];
  for (final amplitude in amplitudes) {
    values
      ..addAll(List<double>.filled(15, 0))
      ..addAll(List<double>.filled(30, amplitude))
      ..addAll(List<double>.filled(15, 0));
  }
  values.addAll(List<double>.filled(10, 0));

  for (var index = 0; index < values.length; index++) {
    controller.handleSampleForTesting(
      EmgSample(
        env: 100 + values[index],
        deviceMs: index * 20,
        seq: index,
        missingSamples: index == 0 ? missingSamples : 0,
      ),
    );
  }
}

List<ComparisonActionPlan> _plans(int count) {
  return List.generate(
    count,
    (index) => ComparisonActionPlan(id: 'action-$index', name: 'Action $index'),
  );
}

class _MemoryHistoryRepository implements ComparisonHistoryRepository {
  final records = <ComparisonHistoryRecord>[];

  @override
  Future<List<ComparisonHistoryRecord>> loadRecords() async {
    return List.unmodifiable(records);
  }

  @override
  Future<void> saveCompleted(ComparisonHistoryRecord record) async {
    records
      ..removeWhere((existing) => existing.id == record.id)
      ..add(record);
  }
}
