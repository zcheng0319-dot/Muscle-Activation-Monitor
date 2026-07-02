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
    this.connected = true,
  });

  final String side;
  final int value;
  final int peak;
  final double average;
  final Color color;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final displayValue = connected ? value : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
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
                  side,
                  style: AppTypography.label.copyWith(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                connected ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                color: connected
                    ? AppColors.primary.withValues(alpha: 0.82)
                    : AppColors.muted,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
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
                  '$displayValue',
                  key: ValueKey(displayValue),
                  style: AppTypography.metric.copyWith(
                    fontSize: 35,
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
                  key: const ValueKey('activation-percent-text'),
                  style: AppTypography.cardTitle.copyWith(
                    color: AppColors.secondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            connected
                ? 'AVG ${average.round()}%  |  PEAK $peak%'
                : 'Not Connected',
            key: const ValueKey('activation-status-text'),
            style: AppTypography.label.copyWith(
              fontSize: 9,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Expanded(child: _FluorescentActivationColumn(value: displayValue)),
        ],
      ),
    );
  }
}

class _FluorescentActivationColumn extends StatefulWidget {
  const _FluorescentActivationColumn({required this.value});

  final int value;

  @override
  State<_FluorescentActivationColumn> createState() =>
      _FluorescentActivationColumnState();
}

class _FluorescentActivationColumnState
    extends State<_FluorescentActivationColumn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    _flowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _syncFlowAnimation();
  }

  @override
  void didUpdateWidget(covariant _FluorescentActivationColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFlowAnimation();
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  void _syncFlowAnimation() {
    if (widget.value >= 70) {
      if (!_flowController.isAnimating) {
        _flowController.repeat();
      }
      return;
    }

    if (_flowController.isAnimating) {
      _flowController.stop();
    }
    _flowController.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedValue = widget.value.clamp(0, 100) / 100;

    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: normalizedValue),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (context, animatedValue, _) {
            final fillHeight = constraints.maxHeight * animatedValue;
            final highActivation = animatedValue >= 0.7;
            final glowStrength = highActivation
                ? 0.34 + (animatedValue * 0.18)
                : 0.08 + (animatedValue * 0.16);

            return Center(
              child: SizedBox(
                key: const ValueKey('activation-bar-track'),
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
                    Container(
                      width: 58,
                      height: fillHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.green.withValues(
                              alpha: glowStrength,
                            ),
                            blurRadius: highActivation ? 28 : 16,
                            spreadRadius: highActivation ? 4 : 1,
                          ),
                          BoxShadow(
                            color: AppColors.cyan.withValues(
                              alpha: glowStrength * 0.82,
                            ),
                            blurRadius: highActivation ? 24 : 14,
                            spreadRadius: highActivation ? 3 : 0,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.bottomCenter,
                          minHeight: constraints.maxHeight,
                          maxHeight: constraints.maxHeight,
                          child: AnimatedBuilder(
                            animation: _flowController,
                            builder: (context, _) {
                              final flowOffset = highActivation
                                  ? _flowController.value
                                  : 0.0;

                              return Container(
                                width: 58,
                                height: constraints.maxHeight,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment(-0.5 + flowOffset, 1),
                                    end: Alignment(0.5 - flowOffset, -1),
                                    colors: _fillColors(animatedValue),
                                    stops: const [0, 0.58, 1],
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
                                        Colors.white.withValues(
                                          alpha: highActivation ? 0.48 : 0.26,
                                        ),
                                        Colors.white.withValues(alpha: 0.02),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
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
      },
    );
  }

  List<Color> _fillColors(double value) {
    if (value < 0.35) {
      return [
        AppColors.cyan.withValues(alpha: 0.48),
        AppColors.green.withValues(alpha: 0.58),
        AppColors.green.withValues(alpha: 0.72),
      ];
    }

    if (value < 0.7) {
      return [
        AppColors.cyan.withValues(alpha: 0.82),
        AppColors.green,
        AppColors.orange.withValues(alpha: 0.82),
      ];
    }

    return const [AppColors.cyan, AppColors.green, AppColors.red];
  }
}
