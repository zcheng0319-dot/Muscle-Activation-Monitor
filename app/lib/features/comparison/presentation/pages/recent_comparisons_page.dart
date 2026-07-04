import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/comparison/presentation/controllers/comparison_history_controller.dart';
import 'package:myemg/features/comparison/presentation/pages/comparison_history_detail_page.dart';

class RecentComparisonsPage extends ConsumerWidget {
  const RecentComparisonsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(comparisonHistoryControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recent comparisons')),
      body: _buildBody(context, ref, state),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ComparisonHistoryState state,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref
                    .read(comparisonHistoryControllerProvider.notifier)
                    .refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (state.records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No completed comparisons yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey('recent-comparisons-list'),
      padding: const EdgeInsets.all(16),
      itemCount: state.records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final record = state.records[index];
        return Card(
          child: ListTile(
            key: ValueKey('comparison-history-${record.id}'),
            title: Text(record.targetMuscle),
            subtitle: Text(
              '${_formatDateTime(record.completedAt)} · '
              '${record.trials.length} '
              '${record.trials.length == 1 ? 'action' : 'actions'}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ComparisonHistoryDetailPage(record: record),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
