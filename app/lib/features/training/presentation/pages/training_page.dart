import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
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
    final bottomContentPadding = 144 + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      extendBody: true,
      body: AmbientBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  bottomContentPadding,
                ),
                sliver: SliverList.list(
                  children: [
                    const TrainingHeader(),
                    const SizedBox(height: AppSpacing.lg),
                    const ExerciseSelector(),
                    const SizedBox(height: AppSpacing.xl),
                    BilateralPerformancePanel(state: state),
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
      ),
      bottomNavigationBar: const _MobileBottomArea(),
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

class _MobileBottomArea extends StatelessWidget {
  const _MobileBottomArea();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 18,
            spreadRadius: -8,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, 6),
              child: SessionControls(),
            ),
            NavigationBar(
              height: 58,
              selectedIndex: 0,
              backgroundColor: Colors.transparent,
              indicatorColor: AppColors.primary.withValues(alpha: 0.12),
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              onDestinationSelected: (index) {
                if (index == 0) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('This section is coming soon.'),
                    ),
                  );
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.fitness_center_rounded),
                  label: 'Training',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sensors_rounded),
                  label: 'Devices',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
