import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';
import 'package:myemg/features/training/presentation/widgets/action_ranking_card.dart';
import 'package:myemg/features/training/presentation/widgets/bilateral_performance_panel.dart';
import 'package:myemg/features/training/presentation/widgets/device_status_card.dart';
import 'package:myemg/features/training/presentation/widgets/exercise_selector.dart';
import 'package:myemg/features/training/presentation/widgets/live_summary_card.dart';
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
                  const SizedBox(height: AppSpacing.lg),
                  const ExerciseSelector(),
                  const SizedBox(height: AppSpacing.md),
                  const SessionControls(),
                  const SizedBox(height: AppSpacing.xl),
                  BilateralPerformancePanel(
                    state: state,
                    leftConnected: deviceState.leftDevice.connected,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  LiveSummaryCard(state: state),
                  const SizedBox(height: AppSpacing.md),
                  ActionRankingCard(
                    rankings: state.sortedActionRankings,
                    canClearAll: state.actionRankings.isNotEmpty,
                    onClearAll: () => _confirmClearRankings(context, ref),
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

  Future<void> _confirmClearRankings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear all rankings?'),
          content: const Text('This removes all saved action ranking results.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );

    if (clear == true && context.mounted) {
      await ref.read(trainingControllerProvider.notifier).clearActionRankings();
    }
  }
}
