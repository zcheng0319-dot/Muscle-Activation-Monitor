import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';

class RawWaveformDialog extends StatelessWidget {
  const RawWaveformDialog({required this.samples, super.key});

  final List<EmgSample> samples;

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.sizeOf(context).width - 64)
        .clamp(260.0, 360.0)
        .toDouble();

    return AlertDialog(
      title: const Text('Raw Waveform'),
      content: SizedBox(
        width: dialogWidth,
        height: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _WaveformLegend(),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: samples.length < 2
                      ? const Center(
                          child: Text(
                            'Start a session to collect waveform data.',
                            style: AppTypography.label,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : CustomPaint(
                          painter: _WaveformPainter(samples),
                          size: Size.infinite,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _WaveformLegend extends StatelessWidget {
  const _WaveformLegend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _LegendItem(color: AppColors.orange, label: 'Left'),
        SizedBox(width: AppSpacing.md),
        _LegendItem(color: AppColors.blue, label: 'Right'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.label),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.samples);

  final List<EmgSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    _drawWave(
      canvas: canvas,
      size: size,
      values: samples.map((sample) => sample.left).toList(),
      color: AppColors.orange,
    );
    _drawWave(
      canvas: canvas,
      size: size,
      values: samples.map((sample) => sample.right).toList(),
      color: AppColors.blue,
    );
  }

  void _drawWave({
    required Canvas canvas,
    required Size size,
    required List<int> values,
    required Color color,
  }) {
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final y = size.height - (values[i].clamp(0, 100) / 100 * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas
      ..drawPath(path, glowPaint)
      ..drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}
