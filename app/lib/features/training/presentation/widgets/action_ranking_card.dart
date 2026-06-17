import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class ActionRankingCard extends StatelessWidget {
  const ActionRankingCard({
    required this.rankings,
    required this.onClearAll,
    super.key,
    this.canClearAll = true,
  });

  final List<SessionSummary> rankings;
  final VoidCallback onClearAll;
  final bool canClearAll;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Action Ranking',
                  style: AppTypography.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: canClearAll ? onClearAll : null,
                child: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (rankings.isEmpty)
            const _EmptyRanking()
          else ...[
            const _RankingHeader(),
            const SizedBox(height: AppSpacing.xs),
            ...rankings.indexed.map(
              (entry) => _RankingRow(index: entry.$1, summary: entry.$2),
            ),
          ],
        ],
      ),
    );
  }
}

abstract final class _RankingLayout {
  static const avgWidth = 92.0;
  static const peakWidth = 58.0;
}

class _RankingHeader extends StatelessWidget {
  const _RankingHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(flex: 5, child: Text('Action', style: AppTypography.label)),
        SizedBox(
          width: _RankingLayout.avgWidth,
          child: Text(
            'Avg. Activation',
            style: AppTypography.label,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          width: _RankingLayout.peakWidth,
          child: Text(
            'Peak',
            style: AppTypography.label,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.index, required this.summary});

  final int index;
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: index.isEven ? AppColors.surface : AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary.exerciseName,
              style: AppTypography.cardTitle.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: _RankingLayout.avgWidth,
            child: Text(
              '${summary.averageActivation}%',
              style: AppTypography.cardTitle,
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: _RankingLayout.peakWidth,
            child: Text(
              '${summary.peakActivation}%',
              style: AppTypography.cardTitle,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRanking extends StatelessWidget {
  const _EmptyRanking();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: const Text(
        'Complete a session to rank actions.',
        style: AppTypography.label,
      ),
    );
  }
}
