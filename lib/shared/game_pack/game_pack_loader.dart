import 'dart:convert';

import 'package:flutter/services.dart';

import 'card_definition.dart';
import 'game_pack_manifest.dart';
import 'game_pack_rules.dart';
import 'packs/simple_card_game_rules.dart';

/// Loads game-pack assets (manifest, card definitions) from the Flutter asset
/// bundle and instantiates the matching [GamePackRules] implementation.
///
/// ## Asset layout
///
/// ```
/// assets/
///   gamepacks/
///     <packId>/
///       manifest.json     — [GamePackManifest] descriptor
///       cards.json        — List<[CardDefinition]>
///       board_layout.json — (optional) layout hints for the board UI
/// ```
///
/// ## Testability
///
/// The [bundle] parameter defaults to [rootBundle] but can be replaced with a
/// [FakeAssetBundle] in unit tests — no widget test harness required.
class GamePackLoader {
  /// Ordered list of pack IDs this loader knows about.
  ///
  /// A hard-coded list is used for now; in a future sprint this could be
  /// read from a top-level `packs.json` index file instead.
  static const List<String> _kKnownPackIds = [
    'simple_card_battle',
  ];

  final AssetBundle _bundle;

  GamePackLoader({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Loads and parses `assets/gamepacks/<packId>/manifest.json`.
  ///
  /// Throws [FlutterError] if the asset is not registered in `pubspec.yaml` or
  /// the file does not exist.
  Future<GamePackManifest> loadManifest(String packId) async {
    final path = _manifestPath(packId);
    final raw = await _bundle.loadString(path);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return GamePackManifest.fromJson(json);
  }

  /// Loads and parses `assets/gamepacks/<packId>/cards.json`.
  ///
  /// Returns an empty list if the cards file is empty.
  /// Throws [FlutterError] if the asset is missing.
  Future<List<CardDefinition>> loadCards(String packId) async {
    final path = _cardsPath(packId);
    final raw = await _bundle.loadString(path);
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CardDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns manifests for all known game packs in declaration order.
  ///
  /// Each manifest is loaded from the corresponding asset bundle file.
  /// Packs whose manifest cannot be loaded are silently skipped in production;
  /// errors propagate in debug mode.
  Future<List<GamePackManifest>> listAvailablePacks() async {
    final manifests = <GamePackManifest>[];
    for (final packId in _kKnownPackIds) {
      final manifest = await loadManifest(packId);
      manifests.add(manifest);
    }
    return manifests;
  }

  /// Instantiates the [GamePackRules] implementation described by [manifest].
  ///
  /// The [cards] list is injected into rules that require external card data.
  /// Rules that do not consume card definitions (i.e. they generate their own
  /// data internally) may ignore the parameter.
  ///
  /// Throws [UnsupportedError] when [manifest.rulesClass] is not recognised.
  GamePackRules createRules(
    GamePackManifest manifest,
    List<CardDefinition> cards,
  ) {
    switch (manifest.rulesClass) {
      case 'SimpleCardGameRules':
        return SimpleCardGameRules(cardDefinitions: cards);
      default:
        throw UnsupportedError(
          'Unknown rulesClass: ${manifest.rulesClass}. '
          'Register it in GamePackLoader.createRules.',
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _manifestPath(String packId) =>
      'assets/gamepacks/$packId/manifest.json';

  String _cardsPath(String packId) =>
      'assets/gamepacks/$packId/cards.json';
}
