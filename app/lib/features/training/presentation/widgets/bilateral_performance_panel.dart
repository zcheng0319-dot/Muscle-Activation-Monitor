import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/widgets/activation_panel.dart';
import 'package:myemg/features/training/presentation/widgets/live_summary_card.dart';
import 'package:myemg/features/training/presentation/widgets/raw_waveform_dialog.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class BilateralPerformancePanel extends StatelessWidget {
  const BilateralPerformancePanel({
    required this.state,
    required this.leftConnected,
    required this.signalUnstable,
    required this.onRecalibrate,
    super.key,
  });

  final TrainingState state;
  final bool leftConnected;
  final bool signalUnstable;
  final VoidCallback onRecalibrate;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      hero: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = constraints.maxWidth <= 320 ? 232.0 : 244.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${state.targetMuscleLabel} Activation',
                      style: AppTypography.sectionTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: state.isRunning
                          ? AppColors.selection.withValues(alpha: 0.12)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: state.isRunning
                            ? AppColors.selection
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: state.isRunning
                                ? AppColors.selection
                                : AppColors.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          state.isRunning ? 'LIVE' : 'READY',
                          style: AppTypography.label.copyWith(
                            color: AppColors.secondary,
                            fontSize: 10,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                leftConnected
                    ? 'Real-time muscle load'
                    : 'Connect an EMG device to begin',
                style: AppTypography.label,
              ),
              if (signalUnstable) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  key: const ValueKey('signal-unstable-chip'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.orange.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.orange,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Signal unstable',
                        style: AppTypography.label.copyWith(
                          color: AppColors.secondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('recalibrate-emg-button'),
                      onPressed: onRecalibrate,
                      icon: const Icon(Icons.restart_alt_rounded, size: 15),
                      label: const Text('Recalibrate EMG'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        textStyle: AppTypography.label.copyWith(fontSize: 11),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const RawWaveformDialog(),
                      ),
                      icon: const Icon(Icons.show_chart_rounded, size: 15),
                      label: const Text('View Raw Waveform'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xs,
                        ),
                        textStyle: AppTypography.label.copyWith(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                key: const ValueKey('biceps-dashboard-area'),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                ),
                child: SizedBox(
                  height: panelHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 55,
                        child: ActivationPanel(
                          key: const ValueKey('biceps-activation-panel'),
                          side: state.targetMuscleLabel,
                          value: leftConnected ? state.leftActivation : 0,
                          peak: leftConnected ? state.leftPeak : 0,
                          average: leftConnected ? state.leftAverage : 0,
                          color: AppColors.orange,
                          connected: leftConnected,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 45,
                        child: CompactLiveSummarySection(
                          key: const ValueKey('biceps-live-summary'),
                          state: state,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
