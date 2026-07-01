import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/core/theme/app_colors.dart';
import 'package:myemg/core/theme/app_spacing.dart';
import 'package:myemg/core/theme/app_typography.dart';
import 'package:myemg/features/training/presentation/controllers/training_controller.dart';

class ExerciseSelector extends ConsumerStatefulWidget {
  const ExerciseSelector({super.key});

  @override
  ConsumerState<ExerciseSelector> createState() => _ExerciseSelectorState();
}

class _ExerciseSelectorState extends ConsumerState<ExerciseSelector> {
  bool _selectingExercises = false;

  @override
  Widget build(BuildContext context) {
    final trainingState = ref.watch(trainingControllerProvider);
    final controller = ref.read(trainingControllerProvider.notifier);
    final locked = trainingState.isRunning || trainingState.hasSessionData;

    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _selectingExercises
            ? _SelectorRow(
                key: ValueKey(
                  'exercise-selector-${trainingState.selectedTargetMuscle}',
                ),
                leading: TextButton.icon(
                  key: const ValueKey('back-to-muscles-button'),
                  onPressed: () => setState(() => _selectingExercises = false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text(
                    trainingState.targetMuscleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                items: trainingState.exercises,
                selectedItem: trainingState.selectedExercise,
                disabled: locked,
                addTooltip: 'Add exercise',
                onSelect: controller.selectExercise,
                onLongPress: (exercise) => _showExerciseMenu(
                  context,
                  controller,
                  exercise,
                  trainingState.targetMuscleLabel,
                ),
                onAdd: () => _showNameDialog(
                  context: context,
                  title: 'Add exercise',
                  labelText: 'Exercise name',
                  hintText: 'Enter exercise name',
                  actionLabel: 'Add',
                  onSubmit: (value) async => controller.addExercise(value)
                      ? ExerciseEditResult.success
                      : ExerciseEditResult.invalidName,
                ),
              )
            : _SelectorRow(
                key: const ValueKey('muscle-selector'),
                items: trainingState.targetMuscles,
                selectedItem: trainingState.selectedTargetMuscle,
                disabled: locked,
                addTooltip: 'Add target muscle',
                onSelect: (muscle) {
                  controller.selectTargetMuscle(muscle);
                  setState(() => _selectingExercises = true);
                },
                onLongPress: (muscle) =>
                    _showMuscleMenu(context, controller, muscle),
                onAdd: () => _showNameDialog(
                  context: context,
                  title: 'Add target muscle',
                  labelText: 'Muscle name',
                  hintText: 'Enter muscle name',
                  actionLabel: 'Add',
                  onSubmit: (value) async => controller.addTargetMuscle(value)
                      ? ExerciseEditResult.success
                      : ExerciseEditResult.invalidName,
                  onSuccess: () => setState(() => _selectingExercises = true),
                ),
              ),
      ),
    );
  }

  Future<void> _showMuscleMenu(
    BuildContext context,
    TrainingController controller,
    String muscle,
  ) async {
    final action = await _showEditMenu(context);
    if (!context.mounted || action == null) return;

    if (action == _EditMenuAction.rename) {
      await _showNameDialog(
        context: context,
        initialValue: muscle,
        title: 'Rename muscle',
        labelText: 'Muscle name',
        hintText: 'Enter muscle name',
        actionLabel: 'Rename',
        onSubmit: (value) => controller.renameTargetMuscle(muscle, value),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this muscle?'),
        content: const Text(
          'This will delete all exercises and saved sets for this muscle. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await controller.deleteTargetMuscle(muscle);
    if (!context.mounted) return;
    if (result == ExerciseEditResult.success) {
      setState(() => _selectingExercises = false);
      return;
    }
    _showEditFailure(context, result);
  }

  Future<_EditMenuAction?> _showEditMenu(BuildContext context) {
    return showModalBottomSheet<_EditMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, _EditMenuAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, _EditMenuAction.delete),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExerciseMenu(
    BuildContext context,
    TrainingController controller,
    String exercise,
    String targetMuscle,
  ) async {
    final action = await _showEditMenu(context);
    if (!context.mounted || action == null) return;

    if (action == _EditMenuAction.rename) {
      await _showNameDialog(
        context: context,
        initialValue: exercise,
        title: 'Rename exercise',
        labelText: 'Exercise name',
        hintText: 'Enter exercise name',
        actionLabel: 'Rename',
        onSubmit: (value) => controller.renameExercise(exercise, value),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this exercise?'),
        content: Text(
          'This will also delete its saved sets for $targetMuscle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await controller.deleteExercise(exercise);
    if (!context.mounted || result == ExerciseEditResult.success) return;
    _showEditFailure(context, result);
  }

  Future<void> _showNameDialog({
    required BuildContext context,
    required String title,
    required String labelText,
    required String hintText,
    required String actionLabel,
    required Future<ExerciseEditResult> Function(String value) onSubmit,
    String initialValue = '',
    VoidCallback? onSuccess,
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
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
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

    final resultStatus = await onSubmit(submittedValue);
    if (!context.mounted) return;
    if (resultStatus == ExerciseEditResult.success) {
      onSuccess?.call();
      return;
    }
    _showEditFailure(context, resultStatus);
  }

  void _showEditFailure(BuildContext context, ExerciseEditResult resultStatus) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            resultStatus == ExerciseEditResult.storageFailure
                ? 'Failed to update saved sessions.'
                : 'Use a unique name.',
          ),
        ),
      );
  }
}

enum _EditMenuAction { rename, delete }

class _SelectorRow extends StatelessWidget {
  const _SelectorRow({
    super.key,
    required this.items,
    required this.selectedItem,
    required this.disabled,
    required this.addTooltip,
    required this.onSelect,
    required this.onAdd,
    this.leading,
    this.onLongPress,
  });

  final Widget? leading;
  final List<String> items;
  final String? selectedItem;
  final bool disabled;
  final String addTooltip;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onLongPress;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (leading != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: leading!,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: items.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No exercises yet', style: AppTypography.label),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _SelectorSegment(
                        name: item,
                        selected: item == selectedItem,
                        disabled: disabled,
                        onTap: () => onSelect(item),
                        onLongPress: onLongPress == null
                            ? null
                            : () => onLongPress!(item),
                      );
                    },
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _AddSelectorButton(
            disabled: disabled,
            tooltip: addTooltip,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _SelectorSegment extends StatelessWidget {
  const _SelectorSegment({
    required this.name,
    required this.selected,
    required this.disabled,
    required this.onTap,
    this.onLongPress,
  });

  final String name;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: disabled
          ? 'End session to edit selections'
          : onLongPress == null
          ? 'Select'
          : 'Long press to edit',
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

class _AddSelectorButton extends StatelessWidget {
  const _AddSelectorButton({
    required this.disabled,
    required this.tooltip,
    required this.onPressed,
  });

  final bool disabled;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: disabled ? 'End session to edit selections' : tooltip,
      onPressed: disabled ? null : onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        visualDensity: VisualDensity.compact,
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
