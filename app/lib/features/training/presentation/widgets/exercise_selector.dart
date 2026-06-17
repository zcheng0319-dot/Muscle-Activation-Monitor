import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';

class ExerciseSelector extends ConsumerWidget {
  const ExerciseSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trainingControllerProvider);
    final controller = ref.read(trainingControllerProvider.notifier);
    final locked = state.isRunning || state.hasSessionData;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.exercises.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final exercise = state.exercises[index];
                final selected = exercise == state.selectedExercise;
                return _ExerciseSegment(
                  name: exercise,
                  selected: selected,
                  disabled: locked,
                  onTap: () => controller.selectExercise(exercise),
                  onLongPress: () => _showExerciseDialog(
                    context: context,
                    initialValue: exercise,
                    title: 'Rename action',
                    actionLabel: 'Rename',
                    onSubmit: (value) =>
                        controller.renameExercise(exercise, value),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _AddExerciseButton(
            disabled: locked,
            onPressed: () => _showExerciseDialog(
              context: context,
              title: 'Add action',
              actionLabel: 'Add',
              onSubmit: controller.addExercise,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExerciseDialog({
    required BuildContext context,
    required String title,
    required String actionLabel,
    required bool Function(String value) onSubmit,
    String initialValue = '',
  }) async {
    final textController = TextEditingController(text: initialValue);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Action name',
              hintText: 'Enter action name',
            ),
            onSubmitted: (_) => Navigator.of(context).pop(true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );

    final submittedValue = textController.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      textController.dispose();
    });

    if (result != true || !context.mounted) return;

    final saved = onSubmit(submittedValue);
    if (!saved) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Use a unique action name.')),
        );
    }
  }
}

class _ExerciseSegment extends StatelessWidget {
  const _ExerciseSegment({
    required this.name,
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.onLongPress,
  });

  final String name;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: disabled ? 'End session to edit actions' : 'Long press to edit',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: disabled ? null : onTap,
        onLongPress: disabled ? null : onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.card,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Text(
            name,
            style: AppTypography.cardTitle.copyWith(
              color: selected ? Colors.white : AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _AddExerciseButton extends StatelessWidget {
  const _AddExerciseButton({required this.disabled, required this.onPressed});

  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: disabled ? 'End session to add actions' : 'Add action',
      onPressed: disabled ? null : onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.muted.withValues(alpha: 0.45),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
      ),
      icon: const Icon(Icons.add_rounded),
    );
  }
}
