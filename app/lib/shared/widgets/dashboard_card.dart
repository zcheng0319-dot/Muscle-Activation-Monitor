import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    required this.child,
    super.key,
    this.color,
    this.hero = false,
    this.padding,
  });

  final Widget child;
  final Color? color;
  final bool hero;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = hero ? AppSpacing.controlRadius : AppSpacing.cardRadius;

    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        border: Border.all(color: AppColors.border, width: hero ? 1.4 : 1),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0F172A,
            ).withValues(alpha: hero ? 0.10 : 0.06),
            blurRadius: hero ? 22 : 14,
            spreadRadius: hero ? -10 : -8,
            offset: Offset(0, hero ? 14 : 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      ),
    );
  }
}
