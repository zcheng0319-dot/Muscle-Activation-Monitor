import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/devices/presentation/controllers/device_connection_controller.dart';
import 'package:myemg/features/training/domain/entities/training_state.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';

class TrainingHeader extends ConsumerWidget {
  const TrainingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(
      deviceConnectionControllerProvider.select(
        (state) => state.leftDevice.connected,
      ),
    );
    final targetMuscle = ref.watch(
      trainingControllerProvider.select((state) => state.targetMuscleLabel),
    );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Training', style: AppTypography.pageTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                liveActivationCopy(targetMuscle),
                style: AppTypography.label,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 10,
                spreadRadius: -6,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _StatusDot(connected: connected),
              const SizedBox(width: AppSpacing.sm),
              Text(
                connected ? 'EMG connected' : 'No EMG connected',
                style: AppTypography.label,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: connected ? AppColors.selection : AppColors.red,
        shape: BoxShape.circle,
      ),
    );
  }
}
