import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';

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
        (state) => (running: state.isRunning, hasData: state.hasSessionData),
      ),
    );
    final controller = ref.read(trainingControllerProvider.notifier);

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: controller.toggleSession,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
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
        const SizedBox(width: AppSpacing.sm),
        _HoldEndSessionButton(
          enabled: status.hasData,
          progress: _holdProgress,
          onHoldStart: status.hasData ? _startEndHold : null,
          onHoldCancel: _cancelEndHold,
        ),
      ],
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
      await ref.read(trainingControllerProvider.notifier).endSession();
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
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton.outlined(
                tooltip: null,
                onPressed: null,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
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
                  width: 44,
                  height: 44,
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
