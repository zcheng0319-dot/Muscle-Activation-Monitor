import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/domain/repositories/exercise_catalog_repository.dart';
import 'package:myemg/features/comparison/presentation/controllers/exercise_catalog_controller.dart';
import 'package:myemg/features/comparison/presentation/pages/manage_muscles_page.dart';

void main() {
  testWidgets('muscles and actions can be added, renamed, and deleted', (
    tester,
  ) async {
    final repository = _MemoryCatalogRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseCatalogRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageMusclesPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('add-muscle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('catalog-name-field')),
      'Forearms',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Forearms'), findsOneWidget);

    await tester.tap(find.text('Forearms'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('catalog-name-field')),
      'Wrist Curl',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Wrist Curl'), findsOneWidget);

    final action = repository.catalog.actions.last;
    await tester.tap(find.byKey(ValueKey('rename-action-${action.id}')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('catalog-name-field')),
      'Reverse Wrist Curl',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Reverse Wrist Curl'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('delete-action-${action.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Reverse Wrist Curl'), findsNothing);
  });

  testWidgets(
    'deleting a muscle asks for confirmation and removes its actions',
    (tester) async {
      final repository = _MemoryCatalogRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exerciseCatalogRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: ManageMusclesPage()),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(
          const ValueKey('delete-muscle-${UserExerciseCatalog.bicepsId}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete muscle?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        repository.catalog.muscleById(UserExerciseCatalog.bicepsId),
        isNull,
      );
      expect(
        repository.catalog.actionsForMuscle(UserExerciseCatalog.bicepsId),
        isEmpty,
      );
    },
  );
}

class _MemoryCatalogRepository implements ExerciseCatalogRepository {
  UserExerciseCatalog catalog = UserExerciseCatalog.defaults;

  @override
  Future<ExerciseCatalogLoadResult> loadCatalog() async {
    return ExerciseCatalogLoadResult(catalog: catalog);
  }

  @override
  Future<void> saveCatalog(UserExerciseCatalog catalog) async {
    this.catalog = catalog;
  }
}
