class MuscleDefinition {
  const MuscleDefinition({required this.id, required this.name});

  final String id;
  final String name;

  MuscleDefinition copyWith({String? name}) {
    return MuscleDefinition(id: id, name: name ?? this.name);
  }

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory MuscleDefinition.fromJson(Map<String, Object?> json) {
    return MuscleDefinition(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
    );
  }
}

class ActionDefinition {
  const ActionDefinition({
    required this.id,
    required this.muscleId,
    required this.name,
  });

  final String id;
  final String muscleId;
  final String name;

  ActionDefinition copyWith({String? name}) {
    return ActionDefinition(
      id: id,
      muscleId: muscleId,
      name: name ?? this.name,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'muscleId': muscleId,
    'name': name,
  };

  factory ActionDefinition.fromJson(Map<String, Object?> json) {
    return ActionDefinition(
      id: _requiredString(json, 'id'),
      muscleId: _requiredString(json, 'muscleId'),
      name: _requiredString(json, 'name'),
    );
  }
}

class UserExerciseCatalog {
  const UserExerciseCatalog({
    this.schemaVersion = currentSchemaVersion,
    this.muscles = const [],
    this.actions = const [],
  });

  static const int currentSchemaVersion = 1;

  static const String bicepsId = 'muscle.biceps';
  static const String tricepsId = 'muscle.triceps';
  static const String legsId = 'muscle.legs';

  static const UserExerciseCatalog defaults = UserExerciseCatalog(
    muscles: [
      MuscleDefinition(id: bicepsId, name: 'Biceps'),
      MuscleDefinition(id: tricepsId, name: 'Triceps'),
      MuscleDefinition(id: legsId, name: 'Legs'),
    ],
    actions: [
      ActionDefinition(
        id: 'action.biceps.bicep-curl',
        muscleId: bicepsId,
        name: 'Bicep Curl',
      ),
      ActionDefinition(
        id: 'action.biceps.hammer-curl',
        muscleId: bicepsId,
        name: 'Hammer Curl',
      ),
      ActionDefinition(
        id: 'action.triceps.pushdown',
        muscleId: tricepsId,
        name: 'Triceps Pushdown',
      ),
      ActionDefinition(
        id: 'action.triceps.overhead-extension',
        muscleId: tricepsId,
        name: 'Overhead Extension',
      ),
      ActionDefinition(
        id: 'action.legs.squat',
        muscleId: legsId,
        name: 'Squat',
      ),
      ActionDefinition(
        id: 'action.legs.leg-extension',
        muscleId: legsId,
        name: 'Leg Extension',
      ),
    ],
  );

  final int schemaVersion;
  final List<MuscleDefinition> muscles;
  final List<ActionDefinition> actions;

  MuscleDefinition? muscleById(String? id) {
    if (id == null) return null;
    for (final muscle in muscles) {
      if (muscle.id == id) return muscle;
    }
    return null;
  }

  List<ActionDefinition> actionsForMuscle(String? muscleId) {
    if (muscleId == null) return const [];
    return actions
        .where((action) => action.muscleId == muscleId)
        .toList(growable: false);
  }

  UserExerciseCatalog copyWith({
    List<MuscleDefinition>? muscles,
    List<ActionDefinition>? actions,
  }) {
    return UserExerciseCatalog(
      schemaVersion: schemaVersion,
      muscles: List.unmodifiable(muscles ?? this.muscles),
      actions: List.unmodifiable(actions ?? this.actions),
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'muscles': muscles.map((muscle) => muscle.toJson()).toList(),
    'actions': actions.map((action) => action.toJson()).toList(),
  };

  factory UserExerciseCatalog.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    final rawMuscles = json['muscles'];
    final rawActions = json['actions'];
    if (schemaVersion is! int ||
        schemaVersion != currentSchemaVersion ||
        rawMuscles is! List ||
        rawActions is! List) {
      throw const FormatException('Unsupported exercise catalog.');
    }

    final muscles = rawMuscles
        .map(
          (entry) => MuscleDefinition.fromJson(
            Map<String, Object?>.from(entry as Map),
          ),
        )
        .toList(growable: false);
    final actions = rawActions
        .map(
          (entry) => ActionDefinition.fromJson(
            Map<String, Object?>.from(entry as Map),
          ),
        )
        .toList(growable: false);

    _validateCatalog(muscles, actions);
    return UserExerciseCatalog(
      schemaVersion: schemaVersion,
      muscles: List.unmodifiable(muscles),
      actions: List.unmodifiable(actions),
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid exercise catalog field: $key');
  }
  return value;
}

void _validateCatalog(
  List<MuscleDefinition> muscles,
  List<ActionDefinition> actions,
) {
  final muscleIds = <String>{};
  final muscleNames = <String>{};
  for (final muscle in muscles) {
    if (!muscleIds.add(muscle.id) ||
        !muscleNames.add(_normalizedName(muscle.name)) ||
        !_validName(muscle.name)) {
      throw const FormatException('Invalid muscle catalog entry.');
    }
  }

  final actionIds = <String>{};
  final actionNamesByMuscle = <String, Set<String>>{};
  for (final action in actions) {
    final names = actionNamesByMuscle.putIfAbsent(
      action.muscleId,
      () => <String>{},
    );
    if (!muscleIds.contains(action.muscleId) ||
        !actionIds.add(action.id) ||
        !names.add(_normalizedName(action.name)) ||
        !_validName(action.name)) {
      throw const FormatException('Invalid action catalog entry.');
    }
  }
}

bool _validName(String name) {
  final trimmed = name.trim();
  return trimmed.isNotEmpty && trimmed.length <= 50;
}

String _normalizedName(String name) => name.trim().toLowerCase();
