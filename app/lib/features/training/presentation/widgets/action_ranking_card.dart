import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/session_summary.dart';

class ActionRankingCard extends StatefulWidget {
  const ActionRankingCard({
    required this.rankings,
    required this.sessions,
    required this.onClearAll,
    required this.onDeleteSession,
    super.key,
    this.canClearAll = true,
    this.targetMuscle = 'Biceps',
  });

  final List<SessionSummary> rankings;
  final List<SessionSummary> sessions;
  final Future<bool> Function() onClearAll;
  final Future<bool> Function(SessionSummary summary) onDeleteSession;
  final bool canClearAll;
  final String targetMuscle;

  @override
  State<ActionRankingCard> createState() => _ActionRankingCardState();
}

class _ActionRankingCardState extends State<ActionRankingCard> {
  String? _expandedExercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('action-ranking-card'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _RankingColors.background,
        border: Border.all(color: _RankingColors.border),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14111827),
            blurRadius: 24,
            spreadRadius: -10,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Best Exercises for ${widget.targetMuscle}',
                      style: AppTypography.sectionTitle.copyWith(
                        color: _RankingColors.text,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Ranked by average '
                      '${widget.targetMuscle.toLowerCase()} activation.',
                      style: AppTypography.label.copyWith(
                        color: _RankingColors.mutedText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                key: const ValueKey('clear-action-rankings-button'),
                onPressed: widget.canClearAll ? _handleClearAll : null,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _RankingColors.button,
                  disabledBackgroundColor: _RankingColors.buttonDisabled,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  shape: const StadiumBorder(),
                  textStyle: AppTypography.label.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.rankings.isEmpty)
            const _EmptyRanking()
          else
            ...widget.rankings.indexed.map((entry) {
              final exerciseName = entry.$2.exerciseName;
              final sessions = widget.sessions
                  .where((session) => session.exerciseName == exerciseName)
                  .toList();
              return _ExerciseRankingRow(
                rank: entry.$1 + 1,
                summary: entry.$2,
                sessions: sessions,
                expanded: _expandedExercise == exerciseName,
                onToggle: () {
                  setState(() {
                    _expandedExercise = _expandedExercise == exerciseName
                        ? null
                        : exerciseName;
                  });
                },
                onDeleteSession: _confirmDeleteSession,
              );
            }),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSession(SessionSummary summary) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete this set?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: _RankingColors.delete,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (delete != true || !mounted) return;

    final deletingLastSet =
        widget.sessions
            .where((session) => session.exerciseName == summary.exerciseName)
            .length ==
        1;
    final deleted = await widget.onDeleteSession(summary);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update saved sessions.')),
      );
      return;
    }
    if (deletingLastSet && _expandedExercise == summary.exerciseName) {
      setState(() => _expandedExercise = null);
    }
  }

  Future<void> _handleClearAll() async {
    final cleared = await widget.onClearAll();
    if (cleared && mounted) {
      setState(() => _expandedExercise = null);
    }
  }
}

abstract final class _RankingColors {
  static const background = Color(0xFFFFE978);
  static const text = Color(0xFF111827);
  static const mutedText = Color(0x8C111827);
  static const border = Color(0x1A111827);
  static const rowHighlight = Color(0x38FFFFFF);
  static const rowHighlightSubtle = Color(0x1FFFFFFF);
  static const button = Color(0xFF111827);
  static const buttonDisabled = Color(0x66111827);
  static const best = Color(0xFF166534);
  static const bestBackground = Color(0x2616A34A);
  static const delete = Color(0xFFDC2626);
}

class _ExerciseRankingRow extends StatelessWidget {
  const _ExerciseRankingRow({
    required this.rank,
    required this.summary,
    required this.sessions,
    required this.expanded,
    required this.onToggle,
    required this.onDeleteSession,
  });

  final int rank;
  final SessionSummary summary;
  final List<SessionSummary> sessions;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(SessionSummary summary) onDeleteSession;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(
        color: rank.isOdd
            ? _RankingColors.rowHighlight
            : _RankingColors.rowHighlightSubtle,
        border: Border.all(color: _RankingColors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('ranking-row-${summary.exerciseName}'),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Column(
                        children: [
                          Text(
                            '#$rank',
                            style: AppTypography.cardTitle.copyWith(
                              color: _RankingColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Icon(
                            Icons.remove_rounded,
                            color: _RankingColors.mutedText,
                            size: 15,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.exerciseName,
                            style: AppTypography.cardTitle.copyWith(
                              color: _RankingColors.text,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (rank == 1) ...[
                            const SizedBox(height: 3),
                            const _BestBadge(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _RankingScore(
                      label: 'Avg',
                      value: '${summary.averageActivation}%',
                      emphasized: true,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _RankingScore(
                      label: 'Peak',
                      value: '${summary.peakActivation}%',
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.chevron_right_rounded,
                      color: _RankingColors.text,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: _RankingColors.border),
            Padding(
              key: ValueKey('ranking-details-${summary.exerciseName}'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: sessions.isEmpty
                  ? Text(
                      'Save this session to add it to set history.',
                      style: AppTypography.label.copyWith(
                        color: _RankingColors.mutedText,
                        fontSize: 10,
                      ),
                    )
                  : Column(
                      children: [
                        for (final entry in sessions.indexed)
                          _SavedSetRow(
                            setNumber: entry.$1 + 1,
                            summary: entry.$2,
                            onDelete: () => onDeleteSession(entry.$2),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BestBadge extends StatelessWidget {
  const _BestBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _RankingColors.bestBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          'Best',
          style: AppTypography.label.copyWith(
            color: _RankingColors.best,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RankingScore extends StatelessWidget {
  const _RankingScore({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: emphasized ? 40 : 38,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: AppTypography.label.copyWith(
              color: _RankingColors.mutedText,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.cardTitle.copyWith(
              color: _RankingColors.text,
              fontSize: emphasized ? 15 : 12,
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _SavedSetRow extends StatelessWidget {
  const _SavedSetRow({
    required this.setNumber,
    required this.summary,
    required this.onDelete,
  });

  final int setNumber;
  final SessionSummary summary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final minutes = summary.durationSeconds ~/ 60;
    final seconds = summary.durationSeconds % 60;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0x52FFFFFF),
        border: Border.all(color: _RankingColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Set $setNumber',
                  style: AppTypography.cardTitle.copyWith(
                    color: _RankingColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey(
                  'delete-set-${summary.createdAt?.microsecondsSinceEpoch ?? setNumber}',
                ),
                tooltip: 'Delete set',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: _RankingColors.delete,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _SetMetric(
                  label: 'Avg',
                  value: '${summary.averageActivation}%',
                ),
              ),
              Expanded(
                child: _SetMetric(
                  label: 'Peak',
                  value: '${summary.peakActivation}%',
                ),
              ),
              Expanded(
                child: _SetMetric(
                  label: 'Time',
                  value: '$minutes:${seconds.toString().padLeft(2, '0')}',
                ),
              ),
              Expanded(
                child: _SetMetric(
                  label: 'Reps',
                  value: '${summary.repetitions}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetMetric extends StatelessWidget {
  const _SetMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(
            color: _RankingColors.mutedText,
            fontSize: 9,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: AppTypography.cardTitle.copyWith(
            color: _RankingColors.text,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
        color: _RankingColors.rowHighlight,
        border: Border.all(color: _RankingColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Complete and save a session to rank exercises.',
        style: AppTypography.label.copyWith(color: _RankingColors.mutedText),
      ),
    );
  }
}
