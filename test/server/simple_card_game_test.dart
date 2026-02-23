import 'package:test/test.dart';

import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/game_pack/packs/simple_card_game.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GameState _initialState({
  List<String>? playerIds,
  int handSize = 5,
}) {
  playerIds ??= ['p1', 'p2'];
  return GameState(
    gameId: 'test',
    turn: 0,
    activePlayerId: playerIds.first,
    data: {
      'playerIds': playerIds,
      'handSize': handSize,
      'deck': [],
      'hands': <String, dynamic>{},
      'discardPile': <String>[],
      'scores': {for (final id in playerIds) id: 0},
    },
  );
}

void main() {
  late SimpleCardGame game;
  late GameState initialState;

  setUp(() async {
    game = SimpleCardGame();
    initialState = _initialState();
    await game.initialize(initialState);
  });

  tearDown(() async {
    await game.dispose();
  });

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  group('initialize', () {
    test('deals cards to each player', () async {
      final state = game.currentState;
      final hands = state.data['hands'] as Map;
      expect(hands.containsKey('p1'), isTrue);
      expect(hands.containsKey('p2'), isTrue);
      expect((hands['p1'] as List).length, equals(5));
      expect((hands['p2'] as List).length, equals(5));
    });

    test('deck has fewer cards after dealing', () async {
      final deck = game.currentState.data['deck'] as List;
      // 52-card deck minus 2 × 5 = 42 remaining
      expect(deck.length, equals(42));
    });
  });

  // ---------------------------------------------------------------------------
  // PLAY_CARD
  // ---------------------------------------------------------------------------

  group('PLAY_CARD', () {
    test('valid play removes card from hand and adds to discard', () {
      final hand = List<String>.from(
        (game.currentState.data['hands'] as Map)['p1'] as List,
      );
      final card = hand.first;

      final action = PlayerAction(
        playerId: 'p1',
        type: 'PLAY_CARD',
        data: {'cardId': card},
      );

      expect(game.validateAction(action, game.currentState), isTrue);
      final newState = game.processAction(action, game.currentState);

      final newHand = (newState.data['hands'] as Map)['p1'] as List;
      expect(newHand, isNot(contains(card)));

      final discard = newState.data['discardPile'] as List;
      expect(discard, contains(card));
    });

    test('rejects playing a card not in the player hand', () {
      final action = PlayerAction(
        playerId: 'p1',
        type: 'PLAY_CARD',
        data: {'cardId': 'nonexistent-card'},
      );
      expect(game.validateAction(action, game.currentState), isFalse);
    });

    test('rejects play from a non-active player', () {
      // p2 is not the active player on turn 0
      final hand = List<String>.from(
        (game.currentState.data['hands'] as Map)['p2'] as List,
      );
      final action = PlayerAction(
        playerId: 'p2',
        type: 'PLAY_CARD',
        data: {'cardId': hand.first},
      );
      expect(game.validateAction(action, game.currentState), isFalse);
    });

    test('advances turn to the next player after a play', () {
      final hand = List<String>.from(
        (game.currentState.data['hands'] as Map)['p1'] as List,
      );
      final action = PlayerAction(
        playerId: 'p1',
        type: 'PLAY_CARD',
        data: {'cardId': hand.first},
      );
      final newState = game.processAction(action, game.currentState);
      expect(newState.activePlayerId, equals('p2'));
      expect(newState.turn, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // DRAW_CARD
  // ---------------------------------------------------------------------------

  group('DRAW_CARD', () {
    test('adds a card to the active player hand', () {
      final before = (game.currentState.data['hands'] as Map)['p1'] as List;
      final action = PlayerAction(
        playerId: 'p1',
        type: 'DRAW_CARD',
        data: {},
      );
      expect(game.validateAction(action, game.currentState), isTrue);
      final newState = game.processAction(action, game.currentState);
      final after = (newState.data['hands'] as Map)['p1'] as List;
      expect(after.length, equals(before.length + 1));
    });

    test('deck shrinks by one after draw', () {
      final deckBefore = (game.currentState.data['deck'] as List).length;
      final action = PlayerAction(
        playerId: 'p1',
        type: 'DRAW_CARD',
        data: {},
      );
      final newState = game.processAction(action, game.currentState);
      final deckAfter = (newState.data['deck'] as List).length;
      expect(deckAfter, equals(deckBefore - 1));
    });

    test('draw fails when deck is empty', () {
      // Drain the deck
      var state = game.currentState;
      while ((state.data['deck'] as List).isNotEmpty) {
        final action = PlayerAction(
          playerId: state.activePlayerId,
          type: 'DRAW_CARD',
          data: {},
        );
        if (!game.validateAction(action, state)) break;
        state = game.processAction(action, state);
        // Advance turn manually so we can keep drawing (skip turn check)
      }

      // Find a player with an empty deck scenario and verify validation fails
      // when deck is truly empty.
      final emptyDeckState = state.copyWith(
        data: {...state.data, 'deck': <String>[]},
      );
      final action = PlayerAction(
        playerId: emptyDeckState.activePlayerId,
        type: 'DRAW_CARD',
        data: {},
      );
      expect(game.validateAction(action, emptyDeckState), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Immutability
  // ---------------------------------------------------------------------------

  group('immutability', () {
    test('processAction does not mutate the original state', () {
      final originalHand = List<String>.from(
        (game.currentState.data['hands'] as Map)['p1'] as List,
      );
      final card = originalHand.first;

      game.processAction(
        PlayerAction(playerId: 'p1', type: 'PLAY_CARD', data: {'cardId': card}),
        game.currentState,
      );

      final handAfter = List<String>.from(
        (game.currentState.data['hands'] as Map)['p1'] as List,
      );
      expect(handAfter, equals(originalHand));
    });
  });
}
