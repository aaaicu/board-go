/// Immutable descriptor for a game pack, parsed from `manifest.json`.
///
/// A manifest lives at `assets/gamepacks/<packId>/manifest.json` and is the
/// authoritative source of pack metadata (display name, player limits, etc.).
///
/// The [rulesClass] field is the Dart class name used by [GamePackLoader] to
/// instantiate the correct [GamePackRules] implementation at runtime.
class GamePackManifest {
  /// Stable, unique pack identifier matching the asset directory name.
  /// Example: `'simple_card_battle'`.
  final String id;

  /// English display name.
  final String name;

  /// Korean display name.
  final String nameKo;

  /// Short human-readable description of the game.
  final String description;

  /// Minimum number of players required to start.
  final int minPlayers;

  /// Maximum number of players supported.
  final int maxPlayers;

  /// Rough expected play time in minutes.
  final int estimatedMinutes;

  /// Semantic version string (e.g. `'1.0.0'`).
  final String version;

  /// Dart class name of the corresponding [GamePackRules] implementation.
  /// Used by [GamePackLoader.createRules] to instantiate the correct rules.
  final String rulesClass;

  const GamePackManifest({
    required this.id,
    required this.name,
    required this.nameKo,
    required this.description,
    required this.minPlayers,
    required this.maxPlayers,
    required this.estimatedMinutes,
    required this.version,
    required this.rulesClass,
  });

  factory GamePackManifest.fromJson(Map<String, dynamic> json) =>
      GamePackManifest(
        id: json['id'] as String,
        name: json['name'] as String,
        nameKo: json['nameKo'] as String,
        description: json['description'] as String,
        minPlayers: json['minPlayers'] as int,
        maxPlayers: json['maxPlayers'] as int,
        estimatedMinutes: json['estimatedMinutes'] as int,
        version: json['version'] as String,
        rulesClass: json['rulesClass'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameKo': nameKo,
        'description': description,
        'minPlayers': minPlayers,
        'maxPlayers': maxPlayers,
        'estimatedMinutes': estimatedMinutes,
        'version': version,
        'rulesClass': rulesClass,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GamePackManifest && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GamePackManifest(id: $id, name: $name, version: $version)';
}
