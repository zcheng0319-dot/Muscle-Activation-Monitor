import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/widgets/activation_panel.dart';
import 'package:myemg/features/training/presentation/widgets/raw_waveform_dialog.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class BilateralPerformancePanel extends StatelessWidget {
  const BilateralPerformancePanel({
    required this.state,
    required this.leftConnected,
    super.key,
  });

  final TrainingState state;
  final bool leftConnected;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      hero: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = constraints.maxWidth <= 320 ? 278.0 : 304.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Biceps Activation',
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
              const SizedBox(height: AppSpacing.sm),
              Text(
                leftConnected
                    ? 'Real-time muscle load'
                    : 'Connect an EMG device to begin',
                style: AppTypography.label,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const RawWaveformDialog(),
                  ),
                  icon: const Icon(Icons.show_chart_rounded, size: 16),
                  label: const Text('View Raw Waveform'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    textStyle: AppTypography.label.copyWith(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: panelHeight,
                child: ActivationPanel(
                  side: 'Biceps',
                  value: leftConnected ? state.leftActivation : 0,
                  peak: leftConnected ? state.leftPeak : 0,
                  average: leftConnected ? state.leftAverage : 0,
                  color: AppColors.orange,
                  connected: leftConnected,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
