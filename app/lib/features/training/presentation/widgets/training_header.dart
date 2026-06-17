import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';

class TrainingHeader extends StatelessWidget {
  const TrainingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Training', style: AppTypography.pageTitle),
              SizedBox(height: AppSpacing.xs),
              Text('Live bilateral activation', style: AppTypography.label),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 10,
                spreadRadius: -6,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Row(
            children: [
              _StatusDot(),
              SizedBox(width: AppSpacing.sm),
              Text('2 devices', style: AppTypography.label),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppColors.selection,
        shape: BoxShape.circle,
      ),
    );
  }
}
