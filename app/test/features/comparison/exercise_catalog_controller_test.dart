import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/domain/repositories/exercise_catalog_repository.dart';
import 'package:myemg/features/comparison/presentation/controllers/exercise_catalog_controller.dart';

void main() {
  test(
    'muscle and action CRUD keeps IDs stable and cascades deletion',
    () async {
      final repository = _MemoryCatalogRepository();
      final container = ProviderContainer(
        overrides: [
          exerciseCatalogRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await _load(container);
      final controller = container.read(
        exerciseCatalogControllerProvider.notifier,
      );

      expect(await controller.addMuscle('Forearms'), isTrue);
      var catalog = container.read(exerciseCatalogControllerProvider).catalog;
      final muscle = catalog.muscles.last;
      expect(await controller.renameMuscle(muscle.id, 'Lower arms'), isTrue);
      catalog = container.read(exerciseCatalogControllerProvider).catalog;
      expect(catalog.muscleById(muscle.id)?.name, 'Lower arms');

      expect(await controller.addAction(muscle.id, 'Wrist Curl'), isTrue);
      catalog = container.read(exerciseCatalogControllerProvider).catalog;
      final action = catalog.actionsForMuscle(muscle.id).single;
      expect(
        await controller.renameAction(action.id, 'Reverse Wrist Curl'),
        isTrue,
      );
      catalog = container.read(exerciseCatalogControllerProvider).catalog;
      expect(catalog.actionsForMuscle(muscle.id).single.id, action.id);

      expect(await controller.deleteMuscle(muscle.id), isTrue);
      catalog = container.read(exerciseCatalogControllerProvider).catalog;
      expect(catalog.muscleById(muscle.id), isNull);
      expect(catalog.actionsForMuscle(muscle.id), isEmpty);
    },
  );

  test(
    'duplicate names are rejected using trimmed case-insensitive rules',
    () async {
      final container = ProviderContainer(
        overrides: [
          exerciseCatalogRepositoryProvider.overrideWithValue(
            _MemoryCatalogRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _load(container);
      final controller = container.read(
        exerciseCatalogControllerProvider.notifier,
      );

      expect(await controller.addMuscle('  bIcEpS  '), isFalse);
      expect(
        container.read(exerciseCatalogControllerProvider).errorMessage,
        contains('already exists'),
      );
      controller.clearError();

      expect(
        await controller.addAction(
          UserExerciseCatalog.bicepsId,
          ' bicep curl ',
        ),
        isFalse,
      );
      expect(
        container.read(exerciseCatalogControllerProvider).errorMessage,
        contains('already exists'),
      );
    },
  );

  test('corrupt recovery exposes defaults and a non-blocking notice', () async {
    final container = ProviderContainer(
      overrides: [
        exerciseCatalogRepositoryProvider.overrideWithValue(
          _MemoryCatalogRepository(recoveredFromCorruptStorage: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _load(container);
    final state = container.read(exerciseCatalogControllerProvider);

    expect(state.isLoading, isFalse);
    expect(state.catalog.muscles, hasLength(3));
    expect(state.recoveredFromCorruptStorage, isTrue);
    expect(state.noticeMessage, contains('Defaults'));
  });
}

Future<void> _load(ProviderContainer container) async {
  container.read(exerciseCatalogControllerProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _MemoryCatalogRepository implements ExerciseCatalogRepository {
  _MemoryCatalogRepository({this.recoveredFromCorruptStorage = false});

  final bool recoveredFromCorruptStorage;
  UserExerciseCatalog catalog = UserExerciseCatalog.defaults;

  @override
  Future<ExerciseCatalogLoadResult> loadCatalog() async {
    return ExerciseCatalogLoadResult(
      catalog: catalog,
      recoveredFromCorruptStorage: recoveredFromCorruptStorage,
    );
  }

  @override
  Future<void> saveCatalog(UserExerciseCatalog catalog) async {
    this.catalog = catalog;
  }
}
