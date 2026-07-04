import 'package:myemg/features/comparison/domain/entities/exercise_catalog.dart';

class ExerciseCatalogLoadResult {
  const ExerciseCatalogLoadResult({
    required this.catalog,
    this.recoveredFromCorruptStorage = false,
  });

  final UserExerciseCatalog catalog;
  final bool recoveredFromCorruptStorage;
}

abstract interface class ExerciseCatalogRepository {
  Future<ExerciseCatalogLoadResult> loadCatalog();

  Future<void> saveCatalog(UserExerciseCatalog catalog);
}
