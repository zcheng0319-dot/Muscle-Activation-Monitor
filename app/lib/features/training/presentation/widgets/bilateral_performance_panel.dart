import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/widgets/activation_panel.dart';
import 'package:myemg/features/training/presentation/widgets/raw_waveform_dialog.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class BilateralPerformancePanel extends StatelessWidget {
  const BilateralPerformancePanel({required this.state, super.key});

  final TrainingState state;

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
                      'Bilateral Performance',
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
              const Text(
                'Real-time bilateral muscle load',
                style: AppTypography.label,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        RawWaveformDialog(samples: state.rawSamples),
                  ),
                  icon: const Icon(Icons.show_chart_rounded, size: 18),
                  label: const Text('View Raw Waveform'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: panelHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ActivationPanel(
                        side: 'Left',
                        value: state.leftActivation,
                        peak: state.leftPeak,
                        average: state.leftAverage,
                        color: AppColors.orange,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ActivationPanel(
                        side: 'Right',
                        value: state.rightActivation,
                        peak: state.rightPeak,
                        average: state.rightAverage,
                        color: AppColors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
