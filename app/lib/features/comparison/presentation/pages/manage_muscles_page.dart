import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/presentation/controllers/exercise_catalog_controller.dart';
import 'package:myemg/features/comparison/presentation/pages/manage_actions_page.dart';
import 'package:myemg/features/comparison/presentation/widgets/catalog_name_dialog.dart';

class ManageMusclesPage extends ConsumerWidget {
  const ManageMusclesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exerciseCatalogControllerProvider);
    final busy = state.isLoading || state.isSaving;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage muscles')),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.catalog.muscles.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No muscles yet. Add a muscle to build your exercise library.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              key: const ValueKey('manage-muscles-list'),
              padding: const EdgeInsets.all(16),
              itemCount: state.catalog.muscles.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final muscle = state.catalog.muscles[index];
                final actionCount = state.catalog
                    .actionsForMuscle(muscle.id)
                    .length;
                return ListTile(
                  key: ValueKey('muscle-${muscle.id}'),
                  title: Text(muscle.name),
                  subtitle: Text(
                    '$actionCount ${actionCount == 1 ? 'action' : 'actions'}',
                  ),
                  onTap: busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ManageActionsPage(muscleId: muscle.id),
                          ),
                        ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: ValueKey('rename-muscle-${muscle.id}'),
                        tooltip: 'Rename muscle',
                        onPressed: busy
                            ? null
                            : () => _renameMuscle(context, ref, muscle),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        key: ValueKey('delete-muscle-${muscle.id}'),
                        tooltip: 'Delete muscle',
                        onPressed: busy
                            ? null
                            : () => _deleteMuscle(
                                context,
                                ref,
                                muscle,
                                actionCount,
                              ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-muscle'),
        onPressed: busy ? null : () => _addMuscle(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add muscle'),
      ),
    );
  }

  Future<void> _addMuscle(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          const CatalogNameDialog(title: 'Add muscle', label: 'Muscle name'),
    );
    if (name == null || !context.mounted) return;
    final saved = await ref
        .read(exerciseCatalogControllerProvider.notifier)
        .addMuscle(name);
    if (!saved && context.mounted) _showCatalogError(context, ref);
  }

  Future<void> _renameMuscle(
    BuildContext context,
    WidgetRef ref,
    MuscleDefinition muscle,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => CatalogNameDialog(
        title: 'Rename muscle',
        label: 'Muscle name',
        initialValue: muscle.name,
      ),
    );
    if (name == null || !context.mounted) return;
    final saved = await ref
        .read(exerciseCatalogControllerProvider.notifier)
        .renameMuscle(muscle.id, name);
    if (!saved && context.mounted) _showCatalogError(context, ref);
  }

  Future<void> _deleteMuscle(
    BuildContext context,
    WidgetRef ref,
    MuscleDefinition muscle,
    int actionCount,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete muscle?'),
        content: Text(
          'Delete ${muscle.name} and its $actionCount '
          '${actionCount == 1 ? 'action' : 'actions'}?',
        ),
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
        .deleteMuscle(muscle.id);
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
