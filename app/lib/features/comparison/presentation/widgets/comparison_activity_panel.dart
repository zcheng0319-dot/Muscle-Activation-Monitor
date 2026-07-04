import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/devices/domain/entities/emg_packet.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/shared/widgets/dashboard_card.dart';

class ComparisonActivityPanel extends ConsumerStatefulWidget {
  const ComparisonActivityPanel({
    required this.active,
    required this.baseline,
    super.key,
  });

  final bool active;
  final double baseline;

  @override
  ConsumerState<ComparisonActivityPanel> createState() {
    return _ComparisonActivityPanelState();
  }
}

class _ComparisonActivityPanelState
    extends ConsumerState<ComparisonActivityPanel> {
  static const _maximumVisibleSamples = 300;

  final _values = <double>[];
  final _repaint = ValueNotifier<int>(0);
  final _liveValue = ValueNotifier<double>(0);
  StreamSubscription<EmgSample>? _subscription;
  Timer? _uiTimer;
  double _pendingLiveValue = 0;

  @override
  void initState() {
    super.initState();
    _subscription = ref
        .read(deviceConnectionControllerProvider.notifier)
        .sampleStream(DeviceSide.left)
        .listen(_handleSample);
    _uiTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _refreshDisplay(),
    );
  }

  @override
  void didUpdateWidget(covariant ComparisonActivityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _values.clear();
      _pendingLiveValue = 0;
      _liveValue.value = 0;
      _repaint.value++;
    } else if (!widget.active && oldWidget.active) {
      _pendingLiveValue = 0;
      _liveValue.value = 0;
    }
  }

  void _handleSample(EmgSample sample) {
    if (!widget.active || sample.deviceRestarted) return;
    final adjusted = math.max(0, sample.env - widget.baseline).toDouble();
    _values.add(adjusted);
    if (_values.length > _maximumVisibleSamples) {
      _values.removeRange(0, _values.length - _maximumVisibleSamples);
    }
    _pendingLiveValue = adjusted;
  }

  void _refreshDisplay() {
    if (!mounted || !widget.active) return;
    _liveValue.value = _pendingLiveValue;
    _repaint.value++;
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    unawaited(_subscription?.cancel());
    _repaint.dispose();
    _liveValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      hero: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live local EMG activity', style: AppTypography.sectionTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Rolling adjustedEnv signal after the session baseline is removed.',
            style: AppTypography.label.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          RepaintBoundary(
            key: const ValueKey('comparison-activity-curve'),
            child: SizedBox(
              height: 190,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                ),
                child: CustomPaint(
                  painter: _ActivityCurvePainter(
                    values: _values,
                    repaint: _repaint,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ValueListenableBuilder<double>(
            valueListenable: _liveValue,
            builder: (context, value, _) {
              final rollingMaximum = _values.fold<double>(
                1,
                (maximum, sample) => math.max(maximum, sample),
              );
              final displayFraction = (value / rollingMaximum).clamp(0.0, 1.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Live display',
                          style: AppTypography.cardTitle,
                        ),
                      ),
                      Text(
                        '${value.toStringAsFixed(1)} env units',
                        key: const ValueKey('comparison-live-env-value'),
                        style: AppTypography.label,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      key: const ValueKey('comparison-live-activity-bar'),
                      value: displayFraction,
                      minHeight: 14,
                      color: AppColors.primary,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Real-time feedback only — this bar is not used for ranking.',
                    style: AppTypography.label.copyWith(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActivityCurvePainter extends CustomPainter {
  _ActivityCurvePainter({required this.values, required super.repaint});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) return;
    final maximum = values.fold<double>(
      1,
      (current, value) => math.max(current, value),
    );
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = size.width * index / (values.length - 1);
      final y = size.height - (values[index] / maximum) * size.height;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ActivityCurvePainter oldDelegate) => false;
}
