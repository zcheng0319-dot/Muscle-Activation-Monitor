import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myemg/features/comparison/data/repositories/local_exercise_catalog_repository.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/domain/repositories/exercise_catalog_repository.dart';

final exerciseCatalogRepositoryProvider = Provider<ExerciseCatalogRepository>(
  (ref) => const LocalExerciseCatalogRepository(),
);

final exerciseCatalogControllerProvider =
    NotifierProvider<ExerciseCatalogController, ExerciseCatalogState>(
      ExerciseCatalogController.new,
    );

class ExerciseCatalogState {
  const ExerciseCatalogState({
    this.catalog = UserExerciseCatalog.defaults,
    this.isLoading = true,
    this.isSaving = false,
    this.errorMessage,
    this.noticeMessage,
    this.recoveredFromCorruptStorage = false,
  });

  final UserExerciseCatalog catalog;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? noticeMessage;
  final bool recoveredFromCorruptStorage;

  ExerciseCatalogState copyWith({
    UserExerciseCatalog? catalog,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    String? noticeMessage,
    bool clearNotice = false,
    bool? recoveredFromCorruptStorage,
  }) {
    return ExerciseCatalogState(
      catalog: catalog ?? this.catalog,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
      recoveredFromCorruptStorage:
          recoveredFromCorruptStorage ?? this.recoveredFromCorruptStorage,
    );
  }
}

class ExerciseCatalogController extends Notifier<ExerciseCatalogState> {
  int _idSequence = 0;

  @override
  ExerciseCatalogState build() {
    unawaited(Future<void>.microtask(_loadCatalog));
    return const ExerciseCatalogState();
  }

  Future<bool> addMuscle(String name) async {
    final normalized = _validatedName(name);
    if (normalized == null || state.isLoading) return false;
    if (state.catalog.muscles.any(
      (muscle) => _sameName(muscle.name, normalized),
    )) {
      state = state.copyWith(
        errorMessage: 'A muscle with this name already exists.',
      );
      return false;
    }
    final next = state.catalog.copyWith(
      muscles: [
        ...state.catalog.muscles,
        MuscleDefinition(id: _newId('muscle'), name: normalized),
      ],
    );
    return _save(next);
  }

  Future<bool> renameMuscle(String muscleId, String name) async {
    final normalized = _validatedName(name);
    if (normalized == null || state.isLoading) return false;
    if (state.catalog.muscles.any(
      (muscle) => muscle.id != muscleId && _sameName(muscle.name, normalized),
    )) {
      state = state.copyWith(
        errorMessage: 'A muscle with this name already exists.',
      );
      return false;
    }
    if (state.catalog.muscleById(muscleId) == null) {
      state = state.copyWith(errorMessage: 'This muscle no longer exists.');
      return false;
    }
    final next = state.catalog.copyWith(
      muscles: state.catalog.muscles
          .map(
            (muscle) => muscle.id == muscleId
                ? muscle.copyWith(name: normalized)
                : muscle,
          )
          .toList(growable: false),
    );
    return _save(next);
  }

  Future<bool> deleteMuscle(String muscleId) async {
    if (state.isLoading || state.catalog.muscleById(muscleId) == null) {
      return false;
    }
    final next = state.catalog.copyWith(
      muscles: state.catalog.muscles
          .where((muscle) => muscle.id != muscleId)
          .toList(growable: false),
      actions: state.catalog.actions
          .where((action) => action.muscleId != muscleId)
          .toList(growable: false),
    );
    return _save(next);
  }

  Future<bool> addAction(String muscleId, String name) async {
    final normalized = _validatedName(name);
    if (normalized == null || state.isLoading) return false;
    if (state.catalog.muscleById(muscleId) == null) {
      state = state.copyWith(errorMessage: 'This muscle no longer exists.');
      return false;
    }
    if (state.catalog
        .actionsForMuscle(muscleId)
        .any((action) => _sameName(action.name, normalized))) {
      state = state.copyWith(
        errorMessage:
            'An action with this name already exists for this muscle.',
      );
      return false;
    }
    final next = state.catalog.copyWith(
      actions: [
        ...state.catalog.actions,
        ActionDefinition(
          id: _newId('action'),
          muscleId: muscleId,
          name: normalized,
        ),
      ],
    );
    return _save(next);
  }

  Future<bool> renameAction(String actionId, String name) async {
    final normalized = _validatedName(name);
    if (normalized == null || state.isLoading) return false;
    ActionDefinition? current;
    for (final action in state.catalog.actions) {
      if (action.id == actionId) {
        current = action;
        break;
      }
    }
    if (current == null) {
      state = state.copyWith(errorMessage: 'This action no longer exists.');
      return false;
    }
    if (state.catalog
        .actionsForMuscle(current.muscleId)
        .any(
          (action) =>
              action.id != actionId && _sameName(action.name, normalized),
        )) {
      state = state.copyWith(
        errorMessage:
            'An action with this name already exists for this muscle.',
      );
      return false;
    }
    final next = state.catalog.copyWith(
      actions: state.catalog.actions
          .map(
            (action) => action.id == actionId
                ? action.copyWith(name: normalized)
                : action,
          )
          .toList(growable: false),
    );
    return _save(next);
  }

  Future<bool> deleteAction(String actionId) async {
    if (state.isLoading ||
        !state.catalog.actions.any((action) => action.id == actionId)) {
      return false;
    }
    final next = state.catalog.copyWith(
      actions: state.catalog.actions
          .where((action) => action.id != actionId)
          .toList(growable: false),
    );
    return _save(next);
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  void clearNotice() {
    if (state.noticeMessage != null) {
      state = state.copyWith(clearNotice: true);
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final result = await ref
          .read(exerciseCatalogRepositoryProvider)
          .loadCatalog();
      state = state.copyWith(
        catalog: result.catalog,
        isLoading: false,
        recoveredFromCorruptStorage: result.recoveredFromCorruptStorage,
        noticeMessage: result.recoveredFromCorruptStorage
            ? 'Exercise library could not be read. Defaults are being used temporarily.'
            : null,
        clearNotice: !result.recoveredFromCorruptStorage,
        clearError: true,
      );
    } on Object {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Exercise library could not be loaded.',
      );
    }
  }

  Future<bool> _save(UserExerciseCatalog next) async {
    final previous = state;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      await ref.read(exerciseCatalogRepositoryProvider).saveCatalog(next);
      state = state.copyWith(
        catalog: next,
        isSaving: false,
        recoveredFromCorruptStorage: false,
        clearError: true,
        clearNotice: true,
      );
      return true;
    } on Object {
      state = previous.copyWith(
        isSaving: false,
        errorMessage: 'Exercise library could not be saved.',
      );
      return false;
    }
  }

  String? _validatedName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 50) {
      state = state.copyWith(
        errorMessage: 'Names must contain 1 to 50 characters.',
      );
      return null;
    }
    return normalized;
  }

  bool _sameName(String first, String second) {
    return first.trim().toLowerCase() == second.trim().toLowerCase();
  }

  String _newId(String prefix) {
    return '$prefix.${DateTime.now().microsecondsSinceEpoch}.${_idSequence++}';
  }
}
