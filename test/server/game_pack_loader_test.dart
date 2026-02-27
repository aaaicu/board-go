import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:board_go/shared/game_pack/card_definition.dart';
import 'package:board_go/shared/game_pack/game_pack_loader.dart';
import 'package:board_go/shared/game_pack/game_pack_manifest.dart';
import 'package:board_go/shared/game_pack/packs/simple_card_game_rules.dart';

// ---------------------------------------------------------------------------
// FakeAssetBundle
// ---------------------------------------------------------------------------

/// Minimal [AssetBundle] backed by an in-memory map.
///
/// Returns the mapped string for [loadString]; throws [FlutterError] for
/// unknown keys, matching the behaviour of [rootBundle] in tests.
class FakeAssetBundle extends AssetBundle {
  final Map<String, String> _assets;

  FakeAssetBundle(this._assets);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (_assets.containsKey(key)) return _assets[key]!;
    throw FlutterError('Asset not found: $key');
  }

  @override
  Future<ByteData> load(String key) async {
    // Delegate to loadString for text assets.
    final text = await loadString(key);
    final bytes = utf8.encode(text);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  @override
  void evict(String key) {}
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _kPackId = 'simple_card_battle';

final _kManifestJson = jsonEncode({
  'id': _kPackId,
  'name': 'Simple Card Battle',
  'nameKo': '심플 카드 배틀',
  'description': '손패의 카드를 사용해 점수를 쌓는 간단한 카드 게임',
  'minPlayers': 2,
  'maxPlayers': 4,
  'estimatedMinutes': 15,
  'version': '1.0.0',
  'rulesClass': 'SimpleCardGameRules',
});

/// Minimal 2-card deck used for fast parsing tests.
final _kMinimalCardsJson = jsonEncode([
  {'id': 'clubs_A', 'suit': 'clubs', 'rank': 'A', 'value': 1, 'displayName': '클럽 A'},
  {'id': 'spades_K', 'suit': 'spades', 'rank': 'K', 'value': 13, 'displayName': '스페이드 K'},
]);

/// Full 52-card deck used for count-verification tests.
final _k52CardsJson = jsonEncode(List.generate(52, (i) {
  const suits = ['clubs', 'diamonds', 'hearts', 'spades'];
  const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  final suit = suits[i ~/ 13];
  final rank = ranks[i % 13];
  return {
    'id': '${suit}_$rank',
    'suit': suit,
    'rank': rank,
    'value': i % 13 + 1,
    'displayName': '$suit $rank',
  };
}));

FakeAssetBundle _bundleWith({
  String? manifestJson,
  String? cardsJson,
}) {
  return FakeAssetBundle({
    if (manifestJson != null)
      'assets/gamepacks/$_kPackId/manifest.json': manifestJson,
    if (cardsJson != null)
      'assets/gamepacks/$_kPackId/cards.json': cardsJson,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  // loadManifest
  // ---------------------------------------------------------------------------
  group('GamePackLoader.loadManifest', () {
    test('parses all fields from manifest.json', () async {
      final loader = GamePackLoader(bundle: _bundleWith(manifestJson: _kManifestJson));

      final manifest = await loader.loadManifest(_kPackId);

      expect(manifest.id, 'simple_card_battle');
      expect(manifest.name, 'Simple Card Battle');
      expect(manifest.nameKo, '심플 카드 배틀');
      expect(manifest.description, '손패의 카드를 사용해 점수를 쌓는 간단한 카드 게임');
      expect(manifest.minPlayers, 2);
      expect(manifest.maxPlayers, 4);
      expect(manifest.estimatedMinutes, 15);
      expect(manifest.version, '1.0.0');
      expect(manifest.rulesClass, 'SimpleCardGameRules');
    });

    test('returns GamePackManifest instance', () async {
      final loader = GamePackLoader(bundle: _bundleWith(manifestJson: _kManifestJson));
      final manifest = await loader.loadManifest(_kPackId);
      expect(manifest, isA<GamePackManifest>());
    });

    test('throws FlutterError for unknown packId', () async {
      // Bundle has no entry for 'nonexistent_pack'.
      final loader = GamePackLoader(bundle: FakeAssetBundle({}));

      expect(
        () => loader.loadManifest('nonexistent_pack'),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // loadCards
  // ---------------------------------------------------------------------------
  group('GamePackLoader.loadCards', () {
    test('parses card list from cards.json', () async {
      final loader = GamePackLoader(bundle: _bundleWith(cardsJson: _kMinimalCardsJson));

      final cards = await loader.loadCards(_kPackId);

      expect(cards.length, 2);
      expect(cards.first, isA<CardDefinition>());
    });

    test('parses first card fields correctly', () async {
      final loader = GamePackLoader(bundle: _bundleWith(cardsJson: _kMinimalCardsJson));

      final cards = await loader.loadCards(_kPackId);
      final ace = cards.first;

      expect(ace.id, 'clubs_A');
      expect(ace.suit, 'clubs');
      expect(ace.rank, 'A');
      expect(ace.value, 1);
      expect(ace.displayName, '클럽 A');
    });

    test('parses all 52 cards when a full deck is provided', () async {
      final loader = GamePackLoader(bundle: _bundleWith(cardsJson: _k52CardsJson));

      final cards = await loader.loadCards(_kPackId);

      expect(cards.length, 52);
    });

    test('throws FlutterError for unknown packId', () async {
      final loader = GamePackLoader(bundle: FakeAssetBundle({}));

      expect(
        () => loader.loadCards('nonexistent_pack'),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // createRules
  // ---------------------------------------------------------------------------
  group('GamePackLoader.createRules', () {
    late List<CardDefinition> twoCards;

    setUp(() {
      twoCards = [
        const CardDefinition(id: 'clubs_A', suit: 'clubs', rank: 'A', value: 1, displayName: '클럽 A'),
        const CardDefinition(id: 'spades_K', suit: 'spades', rank: 'K', value: 13, displayName: '스페이드 K'),
      ];
    });

    test('returns SimpleCardGameRules for simple_card_battle', () async {
      final loader = GamePackLoader(bundle: _bundleWith(manifestJson: _kManifestJson));
      final manifest = await loader.loadManifest(_kPackId);

      final rules = loader.createRules(manifest, twoCards);

      expect(rules, isA<SimpleCardGameRules>());
    });

    test('throws UnsupportedError for unknown rulesClass', () async {
      final unknownManifestJson = jsonEncode({
        'id': 'unknown_pack',
        'name': 'Unknown',
        'nameKo': '알 수 없음',
        'description': 'Unknown pack',
        'minPlayers': 2,
        'maxPlayers': 4,
        'estimatedMinutes': 10,
        'version': '1.0.0',
        'rulesClass': 'NonExistentRules',
      });
      final loader = GamePackLoader(
        bundle: FakeAssetBundle({
          'assets/gamepacks/unknown_pack/manifest.json': unknownManifestJson,
        }),
      );
      final manifest = await loader.loadManifest('unknown_pack');

      expect(
        () => loader.createRules(manifest, twoCards),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // listAvailablePacks
  // ---------------------------------------------------------------------------
  group('GamePackLoader.listAvailablePacks', () {
    test('returns at least one pack', () async {
      final loader = GamePackLoader(bundle: _bundleWith(manifestJson: _kManifestJson));

      final packs = await loader.listAvailablePacks();

      expect(packs, isNotEmpty);
    });

    test('first pack id is simple_card_battle', () async {
      final loader = GamePackLoader(bundle: _bundleWith(manifestJson: _kManifestJson));

      final packs = await loader.listAvailablePacks();

      expect(packs.first.id, 'simple_card_battle');
    });

    test('returns GamePackManifest instances', () async {
      final loader = GamePackLoader(bundle: _bundleWith(manifestJson: _kManifestJson));

      final packs = await loader.listAvailablePacks();

      for (final p in packs) {
        expect(p, isA<GamePackManifest>());
      }
    });
  });

  // ---------------------------------------------------------------------------
  // SimpleCardGameRules backward compatibility
  // ---------------------------------------------------------------------------
  group('SimpleCardGameRules backward compatibility', () {
    test('default constructor still works without cardDefinitions', () {
      // This must not throw — existing tests and production code use this path.
      expect(() => const SimpleCardGameRules(), returnsNormally);
    });

    test('packId is unchanged', () {
      const rules = SimpleCardGameRules();
      expect(rules.packId, isNotEmpty);
    });

    test('accepts cardDefinitions override', () {
      const cards = [
        CardDefinition(id: 'clubs_A', suit: 'clubs', rank: 'A', value: 1, displayName: '클럽 A'),
      ];
      expect(() => SimpleCardGameRules(cardDefinitions: cards), returnsNormally);
    });
  });
}
