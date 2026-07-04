import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/presentation/controllers/exercise_catalog_controller.dart';
import 'package:myemg/features/comparison/presentation/widgets/catalog_name_dialog.dart';

class ManageActionsPage extends ConsumerWidget {
  const ManageActionsPage({required this.muscleId, super.key});

  final String muscleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exerciseCatalogControllerProvider);
    final muscle = state.catalog.muscleById(muscleId);
    final actions = state.catalog.actionsForMuscle(muscleId);
    final busy = state.isLoading || state.isSaving;

    return Scaffold(
      appBar: AppBar(title: Text(muscle?.name ?? 'Manage actions')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : muscle == null
          ? const Center(child: Text('This muscle no longer exists.'))
          : actions.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No actions yet. Add at least two actions before comparing.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              key: const ValueKey('manage-actions-list'),
              padding: const EdgeInsets.all(16),
              itemCount: actions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final action = actions[index];
                return ListTile(
                  key: ValueKey('action-${action.id}'),
                  title: Text(action.name),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: ValueKey('rename-action-${action.id}'),
                        tooltip: 'Rename action',
                        onPressed: busy
                            ? null
                            : () => _renameAction(context, ref, action),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        key: ValueKey('delete-action-${action.id}'),
                        tooltip: 'Delete action',
                        onPressed: busy
                            ? null
                            : () => _deleteAction(context, ref, action),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: muscle == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('add-action'),
              onPressed: busy ? null : () => _addAction(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add action'),
            ),
    );
  }

  Future<void> _addAction(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          const CatalogNameDialog(title: 'Add action', label: 'Action name'),
    );
    if (name == null || !context.mounted) return;
    final saved = await ref
        .read(exerciseCatalogControllerProvider.notifier)
        .addAction(muscleId, name);
    if (!saved && context.mounted) _showCatalogError(context, ref);
  }

  Future<void> _renameAction(
    BuildContext context,
    WidgetRef ref,
    ActionDefinition action,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => CatalogNameDialog(
        title: 'Rename action',
        label: 'Action name',
        initialValue: action.name,
      ),
    );
    if (name == null || !context.mounted) return;
    final saved = await ref
        .read(exerciseCatalogControllerProvider.notifier)
        .renameAction(action.id, name);
    if (!saved && context.mounted) _showCatalogError(context, ref);
  }

  Future<void> _deleteAction(
    BuildContext context,
    WidgetRef ref,
    ActionDefinition action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete action?'),
        content: Text('Delete ${action.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final saved = await ref
        .read(exerciseCatalogControllerProvider.notifier)
        .deleteAction(action.id);
    if (!saved && context.mounted) _showCatalogError(context, ref);
  }
}

void _showCatalogError(BuildContext context, WidgetRef ref) {
  final controller = ref.read(exerciseCatalogControllerProvider.notifier);
  final message =
      ref.read(exerciseCatalogControllerProvider).errorMessage ??
      'Exercise library could not be updated.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  controller.clearError();
}
