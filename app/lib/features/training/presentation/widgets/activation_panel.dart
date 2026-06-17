import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';

class ActivationPanel extends StatelessWidget {
  const ActivationPanel({
    required this.side,
    required this.value,
    required this.peak,
    required this.average,
    required this.color,
    super.key,
  });

  final String side;
  final int value;
  final int peak;
  final double average;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        boxShadow: [
          const BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 12,
            spreadRadius: -6,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$side Bicep',
                  style: AppTypography.label.copyWith(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.sensors_rounded,
                color: AppColors.primary.withValues(alpha: 0.82),
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  '$value',
                  key: ValueKey(value),
                  style: AppTypography.metric.copyWith(
                    fontSize: 42,
                    height: 0.95,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 2),
                child: Text(
                  '%',
                  style: AppTypography.cardTitle.copyWith(
                    color: AppColors.secondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'AVG ${average.round()}%  |  PEAK $peak%',
            style: AppTypography.label.copyWith(
              fontSize: 10,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: _FluorescentActivationColumn(value: value)),
        ],
      ),
    );
  }
}

class _FluorescentActivationColumn extends StatelessWidget {
  const _FluorescentActivationColumn({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final normalizedValue = value.clamp(0, 100) / 100;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillHeight = constraints.maxHeight * normalizedValue;

        return Center(
          child: SizedBox(
            width: 74,
            height: constraints.maxHeight,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: 58,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  width: 58,
                  height: fillHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.28),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.24),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minHeight: constraints.maxHeight,
                      maxHeight: constraints.maxHeight,
                      child: Container(
                        width: 58,
                        height: constraints.maxHeight,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.cyan,
                              AppColors.green,
                              AppColors.red,
                            ],
                            stops: [0, 0.58, 1],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.38),
                                Colors.white.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
