import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:myemg/shared/widgets/ambient_background.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class ComparisonHistoryDetailPage extends StatelessWidget {
  const ComparisonHistoryDetailPage({required this.record, super.key});

  final ComparisonHistoryRecord record;

  @override
  Widget build(BuildContext context) {
    final rankedTrials = record.rankedTrials;
    return Scaffold(
      appBar: AppBar(title: const Text('Comparison details')),
      body: AmbientBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            key: const ValueKey('comparison-history-detail'),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              DashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.targetMuscle, style: AppTypography.pageTitle),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Completed ${_formatDateTime(record.completedAt)}',
                      style: AppTypography.label.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Baseline ${record.baseline.toStringAsFixed(1)} · '
                      'Noise ${record.noise.toStringAsFixed(1)}',
                      style: AppTypography.label,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'These results apply only to this electrode placement '
                      'and calibration session.',
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final entry in rankedTrials.indexed) ...[
                _HistoryTrialCard(rank: entry.$1 + 1, trial: entry.$2),
                if (entry.$1 != rankedTrials.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryTrialCard extends StatelessWidget {
  const _HistoryTrialCard({required this.rank, required this.trial});

  final int rank;
  final ComparisonTrialSummary trial;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#$rank', style: AppTypography.sectionTitle),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(trial.actionName, style: AppTypography.cardTitle),
              ),
              Text(
                '${trial.medianRepMean.toStringAsFixed(1)} env units',
                style: AppTypography.label,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              Text('${trial.repCount} reps', style: AppTypography.label),
              Text(
                'Rep p95 median ${trial.medianRepP95.toStringAsFixed(1)}',
                style: AppTypography.label,
              ),
              Text(
                'Missing ${trial.missingSamples}',
                style: AppTypography.label,
              ),
              Text(
                'Near-rail ${trial.maximumClipRatio.toStringAsFixed(4)}',
                style: AppTypography.label,
              ),
              Text(
                'Quality windows ${trial.qualityPacketCount}',
                style: AppTypography.label,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Load ${trial.loadKg?.toStringAsFixed(1) ?? 'not recorded'} kg · '
            'RIR ${trial.rir?.toString() ?? 'not recorded'} · '
            'Planned reps ${trial.plannedReps?.toString() ?? 'not recorded'}',
            style: AppTypography.label.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
