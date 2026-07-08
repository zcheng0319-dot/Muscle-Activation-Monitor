import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_controller.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_history_controller.dart';
import 'package:myemg/features/comparison/presentation/controllers/exercise_catalog_controller.dart';
import 'package:myemg/features/comparison/presentation/pages/manage_muscles_page.dart';
import 'package:myemg/features/comparison/presentation/pages/recent_comparisons_page.dart';
import 'package:myemg/features/comparison/presentation/widgets/comparison_activity_panel.dart';
import 'package:myemg/features/devices/domain/entities/emg_packet.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/shared/widgets/ambient_background.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class ComparisonPage extends ConsumerStatefulWidget {
  const ComparisonPage({required this.onOpenDevices, super.key});

  final VoidCallback onOpenDevices;

  @override
  ConsumerState<ComparisonPage> createState() => _ComparisonPageState();
}

class _ComparisonPageState extends ConsumerState<ComparisonPage>
    with WidgetsBindingObserver {
  String? _targetMuscleId = UserExerciseCatalog.bicepsId;
  final _selectedActions = <_ActionDraft>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached) {
      return;
    }
    _abortIfActive('app_backgrounded');
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final comparisonState = ref.watch(comparisonControllerProvider);
    final catalogState = ref.watch(exerciseCatalogControllerProvider);
    final device = ref.watch(deviceConnectionControllerProvider).leftDevice;
    final historyMenuEnabled =
        comparisonState.phase == ComparisonPhase.setup ||
        comparisonState.phase == ComparisonPhase.completed;
    ref.listen<UserExerciseCatalog>(
      exerciseCatalogControllerProvider.select((state) => state.catalog),
      (_, catalog) => _synchronizeCatalog(catalog),
    );
    ref.listen<String?>(
      exerciseCatalogControllerProvider.select((state) => state.noticeMessage),
      (_, notice) {
        if (notice == null) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showMessage(notice);
          ref.read(exerciseCatalogControllerProvider.notifier).clearNotice();
        });
      },
    );
    final lifecycleAborted =
        _isBackgroundLifecycle(WidgetsBinding.instance.lifecycleState) &&
        _isAbortSensitivePhase(comparisonState.phase);
    if (lifecycleAborted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _abortIfActive('app_backgrounded');
      });
    }
    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const ValueKey('comparison-scroll-view'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              sliver: SliverList.list(
                children: [
                  _ComparisonHeader(
                    historyEnabled: historyMenuEnabled,
                    onOpenHistory: _openRecentComparisons,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (lifecycleAborted)
                    _buildAborted(
                      comparisonState.copyWith(
                        errorMessage: 'app_backgrounded',
                      ),
                    )
                  else if (comparisonState.phase == ComparisonPhase.completed)
                    _buildResults(comparisonState)
                  else if (comparisonState.phase == ComparisonPhase.aborted)
                    _buildAborted(comparisonState)
                  else if (!device.connected)
                    _DeviceGateCard(
                      key: const ValueKey('comparison-device-disconnected'),
                      icon: Icons.bluetooth_disabled_rounded,
                      title: 'Connect My_EMG first',
                      message:
                          'Open Devices and connect the sensor before starting a comparison.',
                      actionLabel: 'Open Devices',
                      onAction: widget.onOpenDevices,
                    )
                  else if (device.protocolVersion == EmgProtocolVersion.unknown)
                    device.protocolDetectionTimedOut
                        ? _DeviceGateCard(
                            key: const ValueKey('comparison-protocol-timeout'),
                            icon: Icons.sync_problem_rounded,
                            title: 'Firmware identification timed out',
                            message:
                                'No valid protocol packet arrived within 5 seconds. Retry, or reconnect the device from Devices.',
                            actionLabel: 'Retry identification',
                            onAction: _retryProtocolIdentification,
                          )
                        : const _DeviceGateCard(
                            key: ValueKey('comparison-protocol-pending'),
                            icon: Icons.sync_rounded,
                            title: 'Identifying firmware',
                            message:
                                'Waiting for the first valid sample from My_EMG.',
                          )
                  else if (device.firmwareUpdateRequired)
                    const _DeviceGateCard(
                      key: ValueKey('comparison-firmware-update-required'),
                      icon: Icons.system_update_alt_rounded,
                      title: 'Firmware update required',
                      message:
                          'This device uses the legacy protocol. Update to the BLE v2 firmware before using Compare.',
                    )
                  else
                    _buildActivePhase(comparisonState, catalogState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePhase(
    ComparisonState state,
    ExerciseCatalogState catalogState,
  ) {
    return switch (state.phase) {
      ComparisonPhase.setup => _buildSetup(state, catalogState),
      ComparisonPhase.calibrating => _buildCalibration(),
      ComparisonPhase.ready ||
      ComparisonPhase.betweenActions => _buildActionReady(state),
      ComparisonPhase.recording => _buildRecording(state),
      ComparisonPhase.review => _buildReview(state),
      ComparisonPhase.completed => _buildResults(state),
      ComparisonPhase.aborted => _buildAborted(state),
    };
  }

  Widget _buildSetup(ComparisonState state, ExerciseCatalogState catalogState) {
    final catalog = catalogState.catalog;
    final targetMuscle = catalog.muscleById(_targetMuscleId);
    final availableActions = catalog.actionsForMuscle(targetMuscle?.id);
    final canManage = !catalogState.isLoading && !catalogState.isSaving;
    final canStart =
        canManage &&
        targetMuscle != null &&
        availableActions.length >= 2 &&
        _selectedActions.length >= 2 &&
        _selectedActions.length <= 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Keep the same sensor placement for every action.',
                style: AppTypography.label.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (catalogState.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (catalog.muscles.isEmpty)
                _CatalogEmptyState(onManage: _openManageLibrary)
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey(
                          'comparison-muscle-selector-state-${targetMuscle?.id}',
                        ),
                        child: DropdownButtonFormField<String>(
                          key: const ValueKey('comparison-muscle-selector'),
                          initialValue: targetMuscle?.id,
                          decoration: const InputDecoration(
                            labelText: 'Target muscle',
                          ),
                          items: catalog.muscles
                              .map(
                                (muscle) => DropdownMenuItem(
                                  value: muscle.id,
                                  child: Text(muscle.name),
                                ),
                              )
                              .toList(),
                          onChanged: canManage
                              ? (muscleId) {
                                  if (muscleId == null ||
                                      muscleId == _targetMuscleId) {
                                    return;
                                  }
                                  setState(() {
                                    _targetMuscleId = muscleId;
                                    _selectedActions.clear();
                                  });
                                }
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton.icon(
                      key: const ValueKey('manage-exercise-library'),
                      onPressed: canManage ? _openManageLibrary : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Manage library'),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              Text('Select 2–4 actions', style: AppTypography.cardTitle),
              const SizedBox(height: AppSpacing.sm),
              if (targetMuscle != null && availableActions.length < 2)
                const Text(
                  'Add at least 2 actions for this muscle in Manage library.',
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: availableActions.map((action) {
                    final selected = _selectedActions.any(
                      (draft) => draft.id == action.id,
                    );
                    return FilterChip(
                      key: ValueKey('select-action-${action.id}'),
                      label: Text(action.name),
                      selected: selected,
                      onSelected: canManage
                          ? (value) => _toggleAction(action, value)
                          : null,
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        if (_selectedActions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          DashboardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Action order and session notes',
                  style: AppTypography.sectionTitle,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Drag before calibration. Load and RIR are recorded only; they do not change the score.',
                  style: AppTypography.label.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.sm),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedActions.length,
                  onReorderItem: _reorderActions,
                  itemBuilder: (context, index) {
                    final action = _selectedActions[index];
                    return _ActionDraftCard(
                      key: ValueKey(action.id),
                      index: index,
                      action: action,
                      onChanged: () => setState(() {}),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _friendlyError(state.errorMessage!),
            style: AppTypography.label.copyWith(color: AppColors.red),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('comparison-start-calibration'),
            onPressed: canStart ? _startCalibration : null,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Start relaxed calibration'),
          ),
        ),
      ],
    );
  }

  Widget _buildCalibration() {
    return DashboardCard(
      key: const ValueKey('comparison-calibration-card'),
      hero: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Keep the target muscle relaxed',
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'The device is preparing and collecting the session baseline. Do not contract or move the cable.',
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Align the sensor with the muscle fibers.',
              style: AppTypography.label.copyWith(color: AppColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: const ValueKey('comparison-cancel-calibration'),
              onPressed: () => ref
                  .read(comparisonControllerProvider.notifier)
                  .cancelCalibration(),
              child: const Text('Cancel calibration'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionReady(ComparisonState state) {
    final action = state.currentAction!;
    return DashboardCard(
      key: const ValueKey('comparison-action-ready'),
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.phase == ComparisonPhase.betweenActions
                ? 'Rest when you need to'
                : 'Calibration complete',
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Next: ${action.name}',
            style: AppTypography.pageTitle.copyWith(fontSize: 21),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Perform the set at your own rhythm. This is not labelled as a standardized repetition.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.md),
          _ActionMetadata(action: action),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('comparison-start-action'),
              onPressed: () => ref
                  .read(comparisonControllerProvider.notifier)
                  .startCurrentAction(),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Start ${action.name}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecording(ComparisonState state) {
    return Column(
      children: [
        ComparisonActivityPanel(active: true, baseline: state.baseline ?? 0),
        const SizedBox(height: AppSpacing.md),
        DashboardCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.currentAction?.name ?? 'Current action',
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'End the action after the final repetition.',
                      style: AppTypography.label,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('comparison-finish-action'),
                onPressed: _finishAction,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('End action'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReview(ComparisonState state) {
    final trial = state.pendingTrial!;
    final planned = trial.action.plannedReps;
    return DashboardCard(
      key: const ValueKey('comparison-rep-review'),
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trial.isValid
                ? 'Review detected repetitions'
                : 'Action recording invalid',
            style: AppTypography.sectionTitle,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Detected ${trial.repCount}'
            '${planned == null ? '' : ', expected $planned'}',
            style: AppTypography.pageTitle.copyWith(fontSize: 21),
          ),
          if (trial.invalidReason != null || state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _friendlyError(trial.invalidReason ?? state.errorMessage!),
              style: AppTypography.label.copyWith(color: AppColors.red),
            ),
          ] else if (trial.hasMinorClipping) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Minor signal clipping '
              '(${(trial.maximumClipRatio * 100).toStringAsFixed(1)}%). '
              'Results may be slightly less reliable.',
              style: AppTypography.label.copyWith(color: AppColors.orange),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (!trial.isValid)
            FilledButton.icon(
              key: const ValueKey('comparison-invalid-retest'),
              onPressed: () => ref
                  .read(comparisonControllerProvider.notifier)
                  .discardAndRetryCurrentAction(),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Discard and retest'),
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: () => ref
                      .read(comparisonControllerProvider.notifier)
                      .acceptCurrentAction(),
                  child: Text('Confirm ${trial.repCount} reps'),
                ),
                OutlinedButton(
                  onPressed: _showRepCorrectionDialog,
                  child: const Text('Correct count'),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(comparisonControllerProvider.notifier)
                      .discardAndRetryCurrentAction(),
                  child: const Text('Discard and retest'),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Changing the count re-runs segmentation. The app will refuse the change if it cannot find enough signal boundaries.',
            style: AppTypography.label.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ComparisonState state) {
    final trials = [...state.completedTrials]
      ..sort((a, b) {
        final aValue = a.medianRepMean ?? -1;
        final bValue = b.medianRepMean ?? -1;
        return bValue.compareTo(aValue);
      });
    final maximum = trials.fold<double>(
      1,
      (value, trial) =>
          value > (trial.medianRepMean ?? 0) ? value : trial.medianRepMean ?? 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DashboardCard(
          key: const ValueKey('comparison-results'),
          hero: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This comparison', style: AppTypography.pageTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sorted by each action’s median whole-rep adjustedEnv mean. '
                'These measurements apply only to this session.',
                style: AppTypography.body,
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final entry in trials.indexed) ...[
                _ResultRow(
                  rank: entry.$1 + 1,
                  trial: entry.$2,
                  maximum: maximum,
                ),
                if (entry.$1 != trials.length - 1)
                  const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'A higher surface EMG envelope here does not prove that an action is universally better or predicts muscle growth.',
          style: AppTypography.label.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetFromFinishedSession,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Set up another comparison'),
          ),
        ),
      ],
    );
  }

  Widget _buildAborted(ComparisonState state) {
    return _DeviceGateCard(
      key: const ValueKey('comparison-aborted'),
      icon: Icons.error_outline_rounded,
      title: 'Comparison ended',
      message:
          'This session was stopped: ${_friendlyError(state.errorMessage ?? 'aborted')}. '
          'Start a new comparison after checking the device.',
      actionLabel: 'Return to setup',
      onAction: _resetFromFinishedSession,
    );
  }

  void _toggleAction(ActionDefinition action, bool selected) {
    if (selected && _selectedActions.length >= 4) {
      _showMessage('This comparison supports up to 4 actions.');
      return;
    }
    setState(() {
      if (selected) {
        _selectedActions.add(_ActionDraft(id: action.id, name: action.name));
      } else {
        _selectedActions.removeWhere((draft) => draft.id == action.id);
      }
    });
  }

  void _reorderActions(int oldIndex, int newIndex) {
    setState(() {
      final action = _selectedActions.removeAt(oldIndex);
      _selectedActions.insert(newIndex, action);
    });
  }

  Future<void> _startCalibration() async {
    final catalog = ref.read(exerciseCatalogControllerProvider).catalog;
    final targetMuscle = catalog.muscleById(_targetMuscleId);
    if (targetMuscle == null) {
      _showMessage('Add a muscle in Manage library before calibrating.');
      return;
    }
    if (catalog.actionsForMuscle(targetMuscle.id).length < 2) {
      _showMessage('Add at least 2 actions for this muscle.');
      return;
    }
    final controller = ref.read(comparisonControllerProvider.notifier);
    final configured = controller.configure(
      targetMuscle: targetMuscle.name,
      actions: _selectedActions.map((action) => action.toPlan()).toList(),
    );
    if (!configured) {
      _showMessage('Choose 2 to 4 valid actions.');
      return;
    }
    final sent = await controller.beginRestCalibration();
    if (!sent && mounted) {
      _showMessage('Relaxed calibration could not be started.');
    }
  }

  Future<void> _retryProtocolIdentification() async {
    final started = await ref
        .read(deviceConnectionControllerProvider.notifier)
        .retryProtocolDetection();
    if (!started && mounted) {
      _showMessage('Firmware identification could not be restarted.');
    }
  }

  void _finishAction() {
    final controller = ref.read(comparisonControllerProvider.notifier);
    if (!controller.finishCurrentAction()) return;
    final reviewState = ref.read(comparisonControllerProvider);
    final trial = reviewState.pendingTrial;
    if (trial == null) return;

    final plannedReps = trial.action.plannedReps;
    final canAutoAccept =
        trial.isValid &&
        plannedReps != null &&
        trial.repCount == plannedReps &&
        trial.totalMissingSamples == 0 &&
        trial.maximumClipRatio == 0 &&
        reviewState.errorMessage == null;
    if (canAutoAccept) controller.acceptCurrentAction();
  }

  Future<void> _showRepCorrectionDialog() async {
    final requestedCount = await showDialog<int>(
      context: context,
      builder: (_) => const _RepCorrectionDialog(),
    );
    if (requestedCount == null || !mounted) return;
    final corrected = ref
        .read(comparisonControllerProvider.notifier)
        .correctRepCount(requestedCount);
    if (!corrected) {
      _showMessage(
        'The signal does not contain enough reliable boundaries for that count.',
      );
    }
  }

  void _resetFromFinishedSession() {
    final targetMuscle = ref
        .read(exerciseCatalogControllerProvider)
        .catalog
        .muscleById(_targetMuscleId);
    final configured = ref
        .read(comparisonControllerProvider.notifier)
        .configure(
          targetMuscle: targetMuscle?.name ?? '',
          actions: _selectedActions.map((action) => action.toPlan()).toList(),
        );
    if (!configured) {
      setState(_selectedActions.clear);
    }
  }

  Future<void> _openManageLibrary() async {
    final phase = ref.read(comparisonControllerProvider).phase;
    if (phase != ComparisonPhase.setup && phase != ComparisonPhase.completed) {
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ManageMusclesPage()));
  }

  void _synchronizeCatalog(UserExerciseCatalog catalog) {
    if (!mounted) return;
    final currentMuscle = catalog.muscleById(_targetMuscleId);
    final nextMuscleId =
        currentMuscle?.id ??
        (catalog.muscles.isEmpty ? null : catalog.muscles.first.id);
    final targetChanged = nextMuscleId != _targetMuscleId;
    final definitions = {
      for (final action in catalog.actionsForMuscle(nextMuscleId))
        action.id: action,
    };
    var selectionChanged = targetChanged;
    if (!targetChanged) {
      selectionChanged = _selectedActions.any(
        (draft) =>
            !definitions.containsKey(draft.id) ||
            definitions[draft.id]!.name != draft.name,
      );
    }
    if (!selectionChanged) return;

    setState(() {
      _targetMuscleId = nextMuscleId;
      if (targetChanged) {
        _selectedActions.clear();
        return;
      }
      _selectedActions.removeWhere(
        (draft) => !definitions.containsKey(draft.id),
      );
      for (final draft in _selectedActions) {
        draft.name = definitions[draft.id]!.name;
      }
    });
  }

  Future<void> _openRecentComparisons() async {
    final phase = ref.read(comparisonControllerProvider).phase;
    if (phase != ComparisonPhase.setup && phase != ComparisonPhase.completed) {
      return;
    }
    ref.invalidate(comparisonHistoryControllerProvider);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecentComparisonsPage()),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _abortIfActive(String reason) {
    final comparisonState = ref.read(comparisonControllerProvider);
    if (!_isAbortSensitivePhase(comparisonState.phase)) return;
    ref.read(comparisonControllerProvider.notifier).abort(reason);
  }

  bool _isAbortSensitivePhase(ComparisonPhase phase) {
    return switch (phase) {
      ComparisonPhase.calibrating ||
      ComparisonPhase.ready ||
      ComparisonPhase.recording ||
      ComparisonPhase.review ||
      ComparisonPhase.betweenActions => true,
      _ => false,
    };
  }

  bool _isBackgroundLifecycle(AppLifecycleState? state) {
    return state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
  }

  String _friendlyError(String reason) {
    return switch (reason) {
      'firmware_update_required' => 'Firmware update required',
      'v2_device_not_ready' => 'BLE v2 device is not ready',
      'calibration_command_failed' => 'Calibration command failed',
      'calibration_timeout' =>
        'Calibration timed out. Check the connection and retry',
      'calibration_quality_not_good' =>
        'Calibration signal quality was not good. Check the sensor and retry',
      'insufficient_samples' => 'Not enough valid samples',
      'clipping_detected' => 'Severe signal clipping was detected',
      'packet_loss_detected' =>
        'BLE samples were lost. This action must be retested',
      'quality_unavailable' =>
        'No complete signal-quality window was received. This action must be retested',
      'low_confidence' =>
        'Rep boundaries were not stable across detection thresholds. This action must be retested',
      'unstable_baseline' => 'The relaxed baseline was unstable',
      'no_activity' || 'no_valid_reps' => 'No reliable repetitions detected',
      'requested_count_unavailable' =>
        'The requested count could not be supported by signal boundaries',
      'device_disconnected' => 'the device disconnected',
      'device_restarted' => 'the device restarted',
      'left_compare_page' => 'you left Compare during an active session',
      'app_backgrounded' => 'the app moved to the background',
      'system_back' => 'the system back action interrupted the session',
      _ => reason.replaceAll('_', ' '),
    };
  }
}

class _RepCorrectionDialog extends StatefulWidget {
  const _RepCorrectionDialog();

  @override
  State<_RepCorrectionDialog> createState() => _RepCorrectionDialogState();
}

class _RepCorrectionDialogState extends State<_RepCorrectionDialog> {
  final _textController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correct repetition count'),
      content: TextField(
        controller: _textController,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Total repetitions',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Re-segment')),
      ],
    );
  }

  void _submit() {
    final requestedCount = int.tryParse(_textController.text.trim());
    if (requestedCount == null || requestedCount <= 0) {
      setState(() {
        _errorText = 'Enter a whole number greater than zero.';
      });
      return;
    }
    Navigator.of(context).pop(requestedCount);
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader({
    required this.historyEnabled,
    required this.onOpenHistory,
  });

  final bool historyEnabled;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Text('Compare', style: AppTypography.pageTitle)),
        PopupMenuButton<String>(
          key: const ValueKey('comparison-overflow-menu'),
          enabled: historyEnabled,
          tooltip: historyEnabled
              ? 'More'
              : 'Unavailable during an active comparison',
          onSelected: (_) => onOpenHistory(),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'recent-comparisons',
              child: Text('Recent comparisons'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CatalogEmptyState extends StatelessWidget {
  const _CatalogEmptyState({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your exercise library is empty. Add a muscle and at least 2 actions.',
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const ValueKey('manage-empty-exercise-library'),
          onPressed: onManage,
          icon: const Icon(Icons.add),
          label: const Text('Manage library'),
        ),
      ],
    );
  }
}

class _DeviceGateCard extends StatelessWidget {
  const _DeviceGateCard({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      hero: true,
      child: Column(
        children: [
          Icon(icon, size: 46, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(message, style: AppTypography.body, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ActionDraft {
  _ActionDraft({required this.id, required this.name});

  final String id;
  String name;
  double? loadKg;
  int? rir;
  int? plannedReps = 10;

  ComparisonActionPlan toPlan() {
    return ComparisonActionPlan(
      id: id,
      name: name,
      loadKg: loadKg,
      rir: rir,
      plannedReps: plannedReps,
    );
  }
}

class _ActionDraftCard extends StatelessWidget {
  const _ActionDraftCard({
    required this.index,
    required this.action,
    required this.onChanged,
    super.key,
  });

  final int index;
  final _ActionDraft action;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.drag_handle_rounded),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${index + 1}. ${action.name}',
                    style: AppTypography.cardTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: action.loadKg?.toString() ?? '',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Load kg'),
                    onChanged: (value) {
                      action.loadKg = double.tryParse(value);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    initialValue: action.rir?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'RIR'),
                    onChanged: (value) {
                      action.rir = int.tryParse(value);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    initialValue: action.plannedReps?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Planned reps',
                    ),
                    onChanged: (value) {
                      action.plannedReps = int.tryParse(value);
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionMetadata extends StatelessWidget {
  const _ActionMetadata({required this.action});

  final ComparisonActionPlan action;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          'Load: ${action.loadKg?.toStringAsFixed(1) ?? 'not recorded'} kg',
          style: AppTypography.label,
        ),
        Text(
          'RIR: ${action.rir?.toString() ?? 'not recorded'}',
          style: AppTypography.label,
        ),
        Text(
          'Planned reps: ${action.plannedReps?.toString() ?? 'not recorded'}',
          style: AppTypography.label,
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.rank,
    required this.trial,
    required this.maximum,
  });

  final int rank;
  final ActionTrial trial;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final value = trial.medianRepMean ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('#$rank', style: AppTypography.sectionTitle),
            ),
            Expanded(
              child: Text(trial.action.name, style: AppTypography.cardTitle),
            ),
            Text(
              '${value.toStringAsFixed(1)} env units',
              style: AppTypography.label,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (value / maximum).clamp(0.0, 1.0),
            minHeight: 12,
            color: AppColors.primary,
            backgroundColor: AppColors.border,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${trial.repCount} reps · '
          'missing samples ${trial.totalMissingSamples} · '
          'near-rail ratio ${trial.maximumClipRatio.toStringAsFixed(4)} · '
          'quality windows ${trial.qualityPacketCount}',
          style: AppTypography.label.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        _ActionMetadata(action: trial.action),
      ],
    );
  }
}
