import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';

Future<bool> showTrainingCalibrationCountdown({
  required BuildContext context,
  required String title,
  required String message,
  required int seconds,
}) async {
  final completed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TrainingCalibrationCountdownDialog(
      title: title,
      message: message,
      seconds: seconds,
    ),
  );

  return completed ?? false;
}

class _TrainingCalibrationCountdownDialog extends StatefulWidget {
  const _TrainingCalibrationCountdownDialog({
    required this.title,
    required this.message,
    required this.seconds,
  });

  final String title;
  final String message;
  final int seconds;

  @override
  State<_TrainingCalibrationCountdownDialog> createState() =>
      _TrainingCalibrationCountdownDialogState();
}

class _TrainingCalibrationCountdownDialogState
    extends State<_TrainingCalibrationCountdownDialog> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 1) {
        timer.cancel();
        Navigator.of(context).pop(true);
        return;
      }

      setState(() => _remainingSeconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remainingSeconds / widget.seconds;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    color: AppColors.primary,
                    backgroundColor: AppColors.border,
                  ),
                  Text(
                    '$_remainingSeconds',
                    style: AppTypography.metric.copyWith(fontSize: 34),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Keep the sensor still until the countdown finishes.',
            style: AppTypography.label,
          ),
        ],
      ),
    );
  }
}
