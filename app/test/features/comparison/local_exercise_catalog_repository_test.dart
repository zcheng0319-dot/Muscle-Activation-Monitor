import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/data/repositories/local_exercise_catalog_repository.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('first load writes the fixed default catalog', () async {
    const repository = LocalExerciseCatalogRepository();

    final result = await repository.loadCatalog();

    expect(result.recoveredFromCorruptStorage, isFalse);
    expect(
      result.catalog.muscles.map((muscle) => muscle.id),
      containsAll([
        UserExerciseCatalog.bicepsId,
        UserExerciseCatalog.tricepsId,
        UserExerciseCatalog.legsId,
      ]),
    );
    expect(
      result.catalog.actions.map((action) => action.id),
      containsAll([
        'action.biceps.bicep-curl',
        'action.biceps.hammer-curl',
        'action.triceps.pushdown',
        'action.triceps.overhead-extension',
        'action.legs.squat',
        'action.legs.leg-extension',
      ]),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(LocalExerciseCatalogRepository.storageKey),
      isNotNull,
    );
  });

  test('saved catalog is restored on the next load', () async {
    const repository = LocalExerciseCatalogRepository();
    const catalog = UserExerciseCatalog(
      muscles: [MuscleDefinition(id: 'muscle.custom', name: 'Forearms')],
      actions: [
        ActionDefinition(
          id: 'action.custom.curl',
          muscleId: 'muscle.custom',
          name: 'Wrist Curl',
        ),
      ],
    );

    await repository.saveCatalog(catalog);
    final restored = await repository.loadCatalog();

    expect(restored.catalog.muscles.single.id, 'muscle.custom');
    expect(restored.catalog.actions.single.name, 'Wrist Curl');
  });

  test(
    'corrupt JSON uses defaults without overwriting the stored value',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalExerciseCatalogRepository.storageKey: '{broken json',
      });
      const repository = LocalExerciseCatalogRepository();

      final result = await repository.loadCatalog();

      expect(result.recoveredFromCorruptStorage, isTrue);
      expect(result.catalog.muscles, hasLength(3));
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(LocalExerciseCatalogRepository.storageKey),
        '{broken json',
      );
    },
  );
}
