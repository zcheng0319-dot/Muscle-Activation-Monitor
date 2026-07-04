import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/comparison/data/repositories/local_comparison_history_repository.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_history_record.dart';
import 'package:myemg/features/comparison/domain/entities/comparison_session.dart';
import 'package:myemg/features/comparison/domain/repositories/comparison_history_repository.dart';

final comparisonHistoryRepositoryProvider =
    Provider<ComparisonHistoryRepository>(
      (ref) => const LocalComparisonHistoryRepository(),
    );

final comparisonHistoryControllerProvider =
    NotifierProvider<ComparisonHistoryController, ComparisonHistoryState>(
      ComparisonHistoryController.new,
    );

class ComparisonHistoryState {
  const ComparisonHistoryState({
    this.records = const [],
    this.isLoading = true,
    this.isSaving = false,
    this.errorMessage,
  });

  final List<ComparisonHistoryRecord> records;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  ComparisonHistoryState copyWith({
    List<ComparisonHistoryRecord>? records,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ComparisonHistoryState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ComparisonHistoryController extends Notifier<ComparisonHistoryState> {
  Future<void> _initialLoad = Future.value();

  @override
  ComparisonHistoryState build() {
    _initialLoad = Future<void>.microtask(_loadRecords);
    unawaited(_initialLoad);
    return const ComparisonHistoryState();
  }

  Future<void> recordCompletedSession(ComparisonSession session) async {
    if (!session.isComplete) return;
    await _initialLoad;
    final record = ComparisonHistoryRecord.fromCompletedSession(session);
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final repository = ref.read(comparisonHistoryRepositoryProvider);
      await repository.saveCompleted(record);
      final records = await repository.loadRecords();
      state = state.copyWith(
        records: records,
        isLoading: false,
        isSaving: false,
        clearError: true,
      );
    } on Object {
      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        errorMessage: 'Comparison history could not be saved.',
      );
    }
  }

  Future<void> refresh() => _loadRecords();

  Future<void> _loadRecords() async {
    try {
      final records = await ref
          .read(comparisonHistoryRepositoryProvider)
          .loadRecords();
      state = state.copyWith(
        records: records,
        isLoading: false,
        clearError: true,
      );
    } on Object {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Comparison history could not be loaded.',
      );
    }
  }
}
