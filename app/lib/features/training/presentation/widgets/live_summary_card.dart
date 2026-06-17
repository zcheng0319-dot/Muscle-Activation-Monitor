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
    final total = state.leftActivation + state.rightActivation;
    final leftRatio = total == 0 ? .5 : state.leftActivation / total;
    final leftFlex = (leftRatio * 100).round().clamp(1, 99).toInt();
    final difference = state.difference;
    final balanceLabel = difference <= 5
        ? 'Balanced'
        : '${state.leftActivation > state.rightActivation ? 'Left' : 'Right'} +$difference%';
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
              Flexible(
                child: Text(
                  balanceLabel,
                  style: AppTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${state.balanceScore}',
                style: AppTypography.metric.copyWith(
                  fontSize: 28,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Muscle Balance Score',
                  style: AppTypography.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _InlineMetric(
                label: 'Time',
                value: '$minutes:${seconds.toString().padLeft(2, '0')}',
              ),
              const SizedBox(width: AppSpacing.md),
              _InlineMetric(label: 'Reps', value: '${state.repetitions}'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: leftFlex,
                    child: const ColoredBox(color: AppColors.orange),
                  ),
                  Expanded(
                    flex: 100 - leftFlex,
                    child: const ColoredBox(color: AppColors.blue),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text('L ${state.leftActivation}%', style: AppTypography.label),
              const Spacer(),
              Text('R ${state.rightActivation}%', style: AppTypography.label),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _CompactMetric(
                  label: 'Left Avg',
                  value: '${state.leftAverage.round()}%',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _CompactMetric(
                  label: 'Right Avg',
                  value: '${state.rightAverage.round()}%',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _CompactMetric(
                  label: 'Peak',
                  value: '${state.leftPeak}/${state.rightPeak}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          value,
          style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
