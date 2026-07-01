import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/widgets/emg_recalibration_dialog.dart';

class SessionControls extends ConsumerStatefulWidget {
  const SessionControls({super.key});

  @override
  ConsumerState<SessionControls> createState() => _SessionControlsState();
}

class _SessionControlsState extends ConsumerState<SessionControls> {
  static const _holdDuration = Duration(milliseconds: 1500);
  static const _tickDuration = Duration(milliseconds: 50);

  Timer? _holdTimer;
  double _holdProgress = 0;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(
      trainingControllerProvider.select(
        (state) => (
          running: state.isRunning,
          hasData: state.hasSessionData,
          targetMuscle: state.targetMuscleLabel,
          hasValidTarget:
              state.selectedTargetMuscle.trim().isNotEmpty &&
              state.targetMuscles.contains(state.selectedTargetMuscle),
          selectedExercise: state.selectedExercise,
          hasValidExercise:
              state.selectedExercise != null &&
              state.exercises.contains(state.selectedExercise),
        ),
      ),
    );
    final hasConnectedDevice = ref.watch(
      deviceConnectionControllerProvider.select(
        (state) => state.leftDevice.connected,
      ),
    );
    final canEndSession = status.running || status.hasData;
    final controller = ref.read(trainingControllerProvider.notifier);

    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: status.running || hasConnectedDevice
                ? ''
                : 'Connect at least one device to start',
            child: FilledButton.icon(
              onPressed: () => _handleSessionPressed(
                status.running,
                status.targetMuscle,
                status.selectedExercise,
                status.hasValidTarget,
                status.hasValidExercise,
                controller,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.muted.withValues(
                  alpha: 0.22,
                ),
                foregroundColor: Colors.white,
                disabledForegroundColor: AppColors.muted,
                elevation: 0,
                shadowColor: AppColors.primary.withValues(alpha: 0.24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                ),
              ),
              icon: Icon(
                status.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(status.running ? 'Pause Session' : 'Start Session'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _HoldEndSessionButton(
          enabled: canEndSession,
          progress: _holdProgress,
          onHoldStart: canEndSession ? _startEndHold : null,
          onHoldCancel: _cancelEndHold,
        ),
      ],
    );
  }

  Future<void> _handleSessionPressed(
    bool isRunning,
    String targetMuscle,
    String? selectedExercise,
    bool hasValidTarget,
    bool hasValidExercise,
    TrainingController controller,
  ) async {
    if (isRunning) {
      controller.toggleSession();
      return;
    }

    debugPrint('Start Session pressed');
    if (!hasValidTarget) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a target muscle before starting.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!hasValidExercise || selectedExercise == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add an exercise for $targetMuscle before starting.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final deviceState = ref.read(deviceConnectionControllerProvider);
    final connected = deviceState.leftDevice.connected;
    debugPrint('My_EMG ${connected ? 'connected' : 'not connected'}');
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect My_EMG before starting a session.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    debugPrint('Start-session calibration dialog opened');
    await showEmgRecalibrationGuideDialog(
      context: context,
      title: 'Prepare Session',
      introText:
          'Before starting this session, we will recalibrate your relaxed baseline and maximum contraction.',
      introSteps: [
        'Keep your ${contractionMuscleCopy(targetMuscle)} completely relaxed.',
        'Contract your ${contractionMuscleCopy(targetMuscle)} as hard as possible.',
        'Training will start automatically after calibration.',
      ],
      startButtonLabel: 'Start Calibration',
      failureMessage: 'Failed to start calibration. Please reconnect My_EMG.',
      onStartRecalibration: () async {
        debugPrint('Sending recalibration command before session');
        final sent = await ref
            .read(deviceConnectionControllerProvider.notifier)
            .sendRecalibrateCommand();
        if (sent) {
          debugPrint('Recalibration command sent');
        }
        return sent;
      },
      onComplete: () async {
        debugPrint('Calibration countdown completed');
        if (!mounted) return;

        final stillConnected = ref
            .read(deviceConnectionControllerProvider)
            .leftDevice
            .connected;
        if (!stillConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('My_EMG disconnected before training started.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        controller.toggleSession();
        debugPrint('Training session started after recalibration');
      },
      targetMuscle: targetMuscle,
    );
  }

  void _startEndHold() {
    _holdTimer?.cancel();
    setState(() => _holdProgress = 0);

    var elapsed = Duration.zero;
    _holdTimer = Timer.periodic(_tickDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      elapsed += _tickDuration;
      final progress = elapsed.inMilliseconds / _holdDuration.inMilliseconds;

      if (progress >= 1) {
        timer.cancel();
        setState(() => _holdProgress = 1);
        _confirmEndSession();
        return;
      }

      setState(() => _holdProgress = progress);
    });
  }

  void _cancelEndHold() {
    if (_holdProgress >= 1) return;
    _holdTimer?.cancel();
    if (mounted) {
      setState(() => _holdProgress = 0);
    }
  }

  Future<void> _confirmEndSession() async {
    _holdTimer?.cancel();

    final save = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save session?'),
          content: const Text(
            'Save this session to Action Ranking and reset live metrics.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    setState(() => _holdProgress = 0);
    if (save == true) {
      final result = await ref
          .read(trainingControllerProvider.notifier)
          .endSession();
      if (!mounted) return;
      if (result == EndSessionResult.notEnoughValidData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not enough valid EMG data to save this session.\n'
              'Please check sensor contact and try again.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _HoldEndSessionButton extends StatelessWidget {
  const _HoldEndSessionButton({
    required this.enabled,
    required this.progress,
    required this.onHoldStart,
    required this.onHoldCancel,
  });

  final bool enabled;
  final double progress;
  final VoidCallback? onHoldStart;
  final VoidCallback onHoldCancel;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled ? 'Hold 1.5 seconds to end session' : 'End Session',
      child: Listener(
        onPointerDown: enabled ? (_) => onHoldStart?.call() : null,
        onPointerUp: enabled ? (_) => onHoldCancel() : null,
        onPointerCancel: enabled ? (_) => onHoldCancel() : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton.outlined(
                tooltip: null,
                onPressed: null,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: enabled ? AppColors.red : AppColors.muted,
                  disabledForegroundColor: enabled
                      ? AppColors.red
                      : AppColors.muted.withValues(alpha: 0.35),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.controlRadius,
                    ),
                  ),
                ),
                icon: const Icon(Icons.stop_rounded),
              ),
              if (enabled && progress > 0)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    color: AppColors.red,
                    backgroundColor: AppColors.border,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
