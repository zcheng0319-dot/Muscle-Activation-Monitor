import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class LiveSummaryCard extends StatelessWidget {
  const LiveSummaryCard({required this.state, super.key});

  final TrainingState state;

  @override
  Widget build(BuildContext context) {
    final minutes = state.elapsedSeconds ~/ 60;
    final seconds = state.elapsedSeconds % 60;

    return DashboardCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'Live Summary',
                  style: AppTypography.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${state.leftActivation}%',
                style: AppTypography.metric.copyWith(
                  fontSize: 28,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _CompactMetric(
                  label: 'Average',
                  value: '${state.leftAverage.round()}%',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _CompactMetric(
                  label: 'Peak',
                  value: '${state.leftPeak}%',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _CompactMetric(
                  label: 'Time',
                  value: '$minutes:${seconds.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _CompactMetric(
                  label: 'Reps',
                  value: '${state.repetitions}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTypography.label.copyWith(fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: AppTypography.cardTitle.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
