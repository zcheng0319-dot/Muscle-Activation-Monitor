import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';
import 'package:myemg/features/training/presentation/widgets/action_ranking_card.dart';
import 'package:myemg/features/training/presentation/widgets/bilateral_performance_panel.dart';
import 'package:myemg/features/training/presentation/widgets/device_status_card.dart';
import 'package:myemg/features/training/presentation/widgets/emg_recalibration_dialog.dart';
import 'package:myemg/features/training/presentation/widgets/exercise_selector.dart';
import 'package:myemg/features/training/presentation/widgets/session_controls.dart';
import 'package:myemg/features/training/presentation/widgets/training_header.dart';
import 'package:myemg/shared/widgets/ambient_background.dart';

class TrainingPage extends ConsumerWidget {
  const TrainingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trainingControllerProvider);
    final deviceState = ref.watch(deviceConnectionControllerProvider);

    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const ValueKey('training-scroll-view'),
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
                  const TrainingHeader(),
                  const SizedBox(height: AppSpacing.md),
                  const ExerciseSelector(),
                  const SizedBox(height: AppSpacing.sm),
                  const SessionControls(),
                  const SizedBox(height: AppSpacing.md),
                  BilateralPerformancePanel(
                    state: state,
                    leftConnected: deviceState.leftDevice.connected,
                    signalUnstable: deviceState.leftDevice.isInvalidSample,
                    onRecalibrate: () => _showRecalibrationGuide(context, ref),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ActionRankingCard(
                    key: ValueKey(
                      'action-ranking-${state.selectedTargetMuscle}',
                    ),
                    rankings: state.sortedActionRankings,
                    sessions: state.currentMuscleSessions,
                    targetMuscle: state.targetMuscleLabel,
                    canClearAll: state.currentMuscleSessions.isNotEmpty,
                    onClearAll: () => _confirmClearRankings(context, ref),
                    onDeleteSession: (summary) => ref
                        .read(trainingControllerProvider.notifier)
                        .deleteSavedSession(summary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const DeviceStatusCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecalibrationGuide(
    BuildContext context,
    WidgetRef ref,
  ) async {
    debugPrint('Recalibrate button pressed');
    await showEmgRecalibrationGuideDialog(
      context: context,
      targetMuscle: ref.read(trainingControllerProvider).targetMuscleLabel,
      onStartRecalibration: () {
        final deviceState = ref.read(deviceConnectionControllerProvider);
        debugPrint(
          'Recalibrate connected device status: '
          '${deviceState.leftDevice.connected}',
        );
        return ref
            .read(deviceConnectionControllerProvider.notifier)
            .sendRecalibrateCommand();
      },
    );
  }

  Future<bool> _confirmClearRankings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final targetMuscle = ref.read(trainingControllerProvider).targetMuscleLabel;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Clear $targetMuscle ranking?'),
          content: Text(
            'This will delete all saved $targetMuscle sets. '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (clear != true || !context.mounted) return false;

    final cleared = await ref
        .read(trainingControllerProvider.notifier)
        .clearActionRankings();
    if (!context.mounted) return cleared;
    if (!cleared) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update saved sessions.')),
      );
    }
    return cleared;
  }
}
