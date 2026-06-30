import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';

class RawWaveformDialog extends ConsumerWidget {
  const RawWaveformDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples = ref.watch(
      trainingControllerProvider.select((state) => state.rawEmgSamples),
    );
    final dialogWidth = (MediaQuery.sizeOf(context).width - 64)
        .clamp(280.0, 420.0)
        .toDouble();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Raw Waveform',
                        style: AppTypography.sectionTitle,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${samples.length} recent BLE samples',
                  style: AppTypography.label,
                ),
                const SizedBox(height: AppSpacing.md),
                if (samples.length < 2)
                  const SizedBox(
                    height: 220,
                    child: Center(
                      child: Text(
                        'Waiting for BLE raw samples.',
                        style: AppTypography.label,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else ...[
                  _RawWaveformChart(
                    title: 'Biceps EMG',
                    color: AppColors.orange,
                    values: samples.map((sample) => sample.left).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RawWaveformChart extends StatelessWidget {
  const _RawWaveformChart({
    required this.title,
    required this.color,
    required this.values,
  });

  final String title;
  final Color color;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final latestValue = values.isEmpty ? 0.0 : values.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(title, style: AppTypography.cardTitle)),
            Text(
              latestValue.toStringAsFixed(1),
              style: AppTypography.label.copyWith(color: AppColors.secondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: CustomPaint(
                painter: _RawWaveformPainter(values: values, color: color),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RawWaveformPainter extends CustomPainter {
  const _RawWaveformPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) return;

    final finiteValues = values.where((value) => value.isFinite).toList();
    if (finiteValues.length < 2) return;

    final minValue = finiteValues.reduce((a, b) => a < b ? a : b);
    final maxValue = finiteValues.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = _normalizedY(
        value: values[i],
        minValue: minValue,
        range: range,
        height: size.height,
      );
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas
      ..drawPath(path, glowPaint)
      ..drawPath(path, linePaint);
  }

  double _normalizedY({
    required double value,
    required double minValue,
    required double range,
    required double height,
  }) {
    if (!value.isFinite || range.abs() < 0.0001) return height / 2;
    final normalized = ((value - minValue) / range).clamp(0.0, 1.0);
    return height - (normalized * height);
  }

  @override
  bool shouldRepaint(covariant _RawWaveformPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
