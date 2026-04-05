import 'dart:convert';

import 'package:flutter/services.dart';

import 'card_definition.dart';
import 'game_pack_manifest.dart';
import 'game_pack_registry.dart';
import 'game_pack_rules.dart';

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
  /// Pack IDs are read from the [GamePackRegistry] instead of being hardcoded.
  List<String> get _knownPackIds => GamePackRegistry.instance.registeredPackIds;

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
    for (final packId in _knownPackIds) {
      try {
        final manifest = await loadManifest(packId);
        manifests.add(manifest);
      } catch (e) {
        // Skip packs that fail to load — avoids one broken manifest from
        // blocking the entire game-pack list.
        assert(() {
          // ignore: avoid_print
          print('[GamePackLoader] Failed to load pack "$packId": $e');
          return true;
        }());
      }
    }
    return manifests;
  }

  /// Instantiates the [GamePackRules] implementation for [manifest].
  ///
  /// Delegates to [GamePackRegistry] — no pack-specific switch statements here.
  /// The [cards] list is injected into rules that require external card data.
  ///
  /// Throws [UnsupportedError] when the pack is not registered.
  GamePackRules createRules(
    GamePackManifest manifest,
    List<CardDefinition> cards,
  ) {
    return GamePackRegistry.instance.createRules(manifest.id, cards: cards);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _manifestPath(String packId) =>
      'assets/gamepacks/$packId/manifest.json';

  String _cardsPath(String packId) =>
      'assets/gamepacks/$packId/cards.json';
}
