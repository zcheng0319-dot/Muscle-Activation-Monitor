import 'dart:async';

import 'package:flutter/material.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';

Future<void> showEmgRecalibrationGuideDialog({
  required BuildContext context,
  required Future<bool> Function() onStartRecalibration,
  String title = 'Recalibrate EMG',
  String introText =
      'This will recalibrate your relaxed baseline and maximum contraction.',
  List<String>? introSteps,
  String startButtonLabel = 'Start Recalibration',
  String failureMessage =
      'Failed to send recalibration command. Please reconnect My_EMG.',
  String completionMessage = 'You can start training now.',
  Future<void> Function()? onComplete,
  String targetMuscle = 'Biceps',
}) {
  final muscle = contractionMuscleCopy(targetMuscle);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmgRecalibrationGuideDialog(
      onStartRecalibration: onStartRecalibration,
      title: title,
      introText: introText,
      introSteps:
          introSteps ??
          [
            'Keep your $muscle completely relaxed.',
            'Contract your $muscle as hard as possible.',
          ],
      startButtonLabel: startButtonLabel,
      failureMessage: failureMessage,
      completionMessage: completionMessage,
      onComplete: onComplete,
      targetMuscle: targetMuscle,
    ),
  );
}

enum _RecalibrationStage {
  introduction,
  sending,
  warmup,
  relax,
  maxContraction,
  complete,
  failed,
}

class _EmgRecalibrationGuideDialog extends StatefulWidget {
  const _EmgRecalibrationGuideDialog({
    required this.onStartRecalibration,
    required this.title,
    required this.introText,
    required this.introSteps,
    required this.startButtonLabel,
    required this.failureMessage,
    required this.completionMessage,
    required this.onComplete,
    required this.targetMuscle,
  });

  final Future<bool> Function() onStartRecalibration;
  final String title;
  final String introText;
  final List<String> introSteps;
  final String startButtonLabel;
  final String failureMessage;
  final String completionMessage;
  final Future<void> Function()? onComplete;
  final String targetMuscle;

  @override
  State<_EmgRecalibrationGuideDialog> createState() =>
      _EmgRecalibrationGuideDialogState();
}

class _EmgRecalibrationGuideDialogState
    extends State<_EmgRecalibrationGuideDialog> {
  _RecalibrationStage _stage = _RecalibrationStage.introduction;
  int _remainingSeconds = 0;

  bool get _canClose {
    return _stage == _RecalibrationStage.introduction ||
        _stage == _RecalibrationStage.complete ||
        _stage == _RecalibrationStage.failed;
  }

  Future<void> _startRecalibration() async {
    setState(() => _stage = _RecalibrationStage.sending);

    final sent = await widget.onStartRecalibration();
    if (!mounted) return;
    if (!sent) {
      setState(() => _stage = _RecalibrationStage.failed);
      return;
    }

    await _runCountdown(_RecalibrationStage.warmup, 2);
    await _runCountdown(_RecalibrationStage.relax, 3);
    await _runCountdown(_RecalibrationStage.maxContraction, 5);
    if (!mounted) return;
    setState(() => _stage = _RecalibrationStage.complete);

    if (widget.onComplete != null) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      await widget.onComplete!();
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _runCountdown(_RecalibrationStage stage, int seconds) async {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _remainingSeconds = seconds;
    });

    for (var remaining = seconds; remaining > 0; remaining--) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _remainingSeconds = remaining - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canClose,
      child: AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(_title, style: AppTypography.sectionTitle),
        content: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildContent(),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildContent() {
    if (_stage == _RecalibrationStage.introduction) {
      return Column(
        key: const ValueKey('recalibration-introduction'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.introText, style: AppTypography.cardTitle),
          const SizedBox(height: AppSpacing.lg),
          for (var index = 0; index < widget.introSteps.length; index++) ...[
            _InstructionStep(number: index + 1, text: widget.introSteps[index]),
            if (index != widget.introSteps.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      );
    }

    if (_stage == _RecalibrationStage.sending) {
      return const Padding(
        key: ValueKey('recalibration-sending'),
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: AppSpacing.md),
              Text(
                'Sending recalibration command...',
                style: AppTypography.cardTitle,
              ),
            ],
          ),
        ),
      );
    }

    if (_stage == _RecalibrationStage.failed) {
      return Text(
        widget.failureMessage,
        key: const ValueKey('recalibration-failed'),
        style: AppTypography.cardTitle,
      );
    }

    if (_stage == _RecalibrationStage.complete) {
      return Column(
        key: const ValueKey('recalibration-complete'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 58,
            color: AppColors.selection,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            widget.completionMessage,
            style: AppTypography.cardTitle,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return Column(
      key: ValueKey(_stage),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _instruction,
          style: AppTypography.cardTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          width: 112,
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.primary, width: 2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$_remainingSeconds',
                key: ValueKey('recalibration-countdown-${_stage.name}'),
                style: AppTypography.metric.copyWith(fontSize: 48),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_stage == _RecalibrationStage.introduction) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _startRecalibration,
          child: Text(widget.startButtonLabel),
        ),
      ];
    }

    if (_stage == _RecalibrationStage.failed) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _startRecalibration,
          child: const Text('Try Again'),
        ),
      ];
    }

    if (_stage == _RecalibrationStage.complete && widget.onComplete == null) {
      return [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ];
    }

    return const [];
  }

  String get _title {
    return switch (_stage) {
      _RecalibrationStage.introduction => widget.title,
      _RecalibrationStage.sending => widget.title,
      _RecalibrationStage.warmup => 'Get ready',
      _RecalibrationStage.relax => 'Relax',
      _RecalibrationStage.maxContraction => 'Max contraction',
      _RecalibrationStage.complete => 'Calibration complete',
      _RecalibrationStage.failed => 'Recalibration failed',
    };
  }

  String get _instruction {
    final muscle = contractionMuscleCopy(widget.targetMuscle);
    return switch (_stage) {
      _RecalibrationStage.warmup => 'Keep the sensor still.',
      _RecalibrationStage.relax => 'Keep your $muscle completely relaxed.',
      _RecalibrationStage.maxContraction =>
        'Contract your $muscle as hard as possible.',
      _ => '',
    };
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.cardTitle)),
      ],
    );
  }
}
