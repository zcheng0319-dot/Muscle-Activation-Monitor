import 'dart:convert';

import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';
import 'package:myemg/features/comparison/domain/repositories/exercise_catalog_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalExerciseCatalogRepository implements ExerciseCatalogRepository {
  const LocalExerciseCatalogRepository();

  static const storageKey = 'comparison.catalog.v1';

  @override
  Future<ExerciseCatalogLoadResult> loadCatalog() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(storageKey);
    if (stored == null) {
      await saveCatalog(UserExerciseCatalog.defaults);
      return const ExerciseCatalogLoadResult(
        catalog: UserExerciseCatalog.defaults,
      );
    }

    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) {
        throw const FormatException('Exercise catalog is not an object.');
      }
      return ExerciseCatalogLoadResult(
        catalog: UserExerciseCatalog.fromJson(
          Map<String, Object?>.from(decoded),
        ),
      );
    } on Object {
      return const ExerciseCatalogLoadResult(
        catalog: UserExerciseCatalog.defaults,
        recoveredFromCorruptStorage: true,
      );
    }
  }

  @override
  Future<void> saveCatalog(UserExerciseCatalog catalog) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      storageKey,
      jsonEncode(catalog.toJson()),
    );
    if (!saved) {
      throw StateError('Exercise catalog could not be saved.');
    }
  }
}
