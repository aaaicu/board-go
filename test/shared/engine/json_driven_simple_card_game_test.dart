import 'dart:math';

import 'package:test/test.dart';

import '../../../lib/shared/game_pack/engine/json_driven_rules.dart';
import '../../../lib/shared/game_pack/engine/packs/simple_card_game_def.dart';
import '../../../lib/shared/game_pack/player_action.dart';
import '../../../lib/shared/game_session/game_session_state.dart';
import '../../../lib/shared/game_session/player_session_state.dart';
import '../../../lib/shared/game_session/session_phase.dart';

void main() {
  group('JsonDrivenRules — SimpleCardGame', () {
    late JsonDrivenRules rules;

    setUp(() {
      rules = JsonDrivenRules(
        definition: simpleCardGameDefinition(),
        rng: Random(42),
      );
    });

    GameSessionState _lobbyState({int playerCount = 2}) {
      final players = <String, PlayerSessionState>{};
      final order = <String>[];
      for (var i = 1; i <= playerCount; i++) {
        final id = 'p$i';
        order.add(id);
        players[id] = PlayerSessionState(
          playerId: id,
          nickname: 'Player$i',
          isConnected: true,
          isReady: false,
          reconnectToken: 'token-$id',
        );
      }
      return GameSessionState(
        sessionId: 'test-session',
        phase: SessionPhase.lobby,
        players: players,
        playerOrder: order,
        version: 0,
        log: [],
      );
    }

    // -----------------------------------------------------------------
    // Pack metadata
    // -----------------------------------------------------------------

    test('packId matches', () {
      expect(rules.packId, 'simple_card_game');
    });

    test('minPlayers / maxPlayers', () {
      expect(rules.minPlayers, 2);
      expect(rules.maxPlayers, 4);
    });

    test('orientations', () {
      expect(rules.boardOrientation, 'landscape');
      expect(rules.nodeOrientation, 'portrait');
    });

    // -----------------------------------------------------------------
    // createInitialGameState
    // -----------------------------------------------------------------

    test('setup creates correct initial state', () {
      final lobby = _lobbyState();
      final state = rules.createInitialGameState(lobby);

      expect(state.phase, SessionPhase.inGame);
      expect(state.gameState, isNotNull);
      expect(state.turnState, isNotNull);

      final data = state.gameState!.data;

      // Deck + hands should total 52 cards
      final deck = data['deck'] as List;
      final hands = data['hands'] as Map;
      final p1Hand = hands['p1'] as List;
      final p2Hand = hands['p2'] as List;
      expect(deck.length + p1Hand.length + p2Hand.length, 52);

      // Each player gets 5 cards
      expect(p1Hand.length, 5);
      expect(p2Hand.length, 5);

      // Deck has 42 remaining (52 - 5*2)
      expect(deck.length, 42);

      // Scores initialized to 0
      final scores = data['scores'] as Map;
      expect(scores['p1'], 0);
      expect(scores['p2'], 0);

      // Discard pile is empty
      expect(data['discardPile'], isEmpty);

      // Turn state
      expect(state.turnState!.round, 1);
      expect(state.turnState!.activePlayerId, 'p1');
    });

    test('setup with 3 players', () {
      final lobby = _lobbyState(playerCount: 3);
      final state = rules.createInitialGameState(lobby);

      final data = state.gameState!.data;
      final deck = data['deck'] as List;
      expect(deck.length, 37); // 52 - 5*3

      final hands = data['hands'] as Map;
      expect(hands.length, 3);
      for (final pid in ['p1', 'p2', 'p3']) {
        expect((hands[pid] as List).length, 5);
      }
    });

    // -----------------------------------------------------------------
    // getAllowedActions
    // -----------------------------------------------------------------

    test('active player has PLAY_CARD + DRAW_CARD + END_TURN', () {
      final state = rules.createInitialGameState(_lobbyState());
      final actions = rules.getAllowedActions(state, 'p1');

      final types = actions.map((a) => a.actionType).toSet();
      expect(types, containsAll(['PLAY_CARD', 'DRAW_CARD', 'END_TURN']));

      // 5 PLAY_CARD actions (one per card in hand)
      final playCards =
          actions.where((a) => a.actionType == 'PLAY_CARD').toList();
      expect(playCards.length, 5);

      // Each PLAY_CARD has a cardId param
      for (final pc in playCards) {
        expect(pc.params['cardId'], isNotNull);
      }
    });

    test('non-active player has no actions', () {
      final state = rules.createInitialGameState(_lobbyState());
      // p2 is not active
      final actions = rules.getAllowedActions(state, 'p2');
      expect(actions, isEmpty);
    });

    // -----------------------------------------------------------------
    // applyAction — PLAY_CARD
    // -----------------------------------------------------------------

    test('PLAY_CARD removes card from hand, adds to discard, increments score', () {
      final state = rules.createInitialGameState(_lobbyState());
      final hand = List<String>.from(
          (state.gameState!.data['hands'] as Map)['p1'] as List);
      final cardToPlay = hand.first;

      final newState = rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'PLAY_CARD', data: {'cardId': cardToPlay}),
      );

      final newData = newState.gameState!.data;
      final newHand = (newData['hands'] as Map)['p1'] as List;
      expect(newHand.length, 4);
      expect(newHand, isNot(contains(cardToPlay)));

      final discard = newData['discardPile'] as List;
      expect(discard, contains(cardToPlay));

      final scores = newData['scores'] as Map;
      expect(scores['p1'], 1);
    });

    // -----------------------------------------------------------------
    // applyAction — DRAW_CARD
    // -----------------------------------------------------------------

    test('DRAW_CARD moves top card from deck to hand', () {
      final state = rules.createInitialGameState(_lobbyState());
      final deckBefore = List<String>.from(state.gameState!.data['deck'] as List);
      final topCard = deckBefore.first;

      final newState = rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'DRAW_CARD', data: {}),
      );

      final newData = newState.gameState!.data;
      final newHand = (newData['hands'] as Map)['p1'] as List;
      expect(newHand.length, 6);
      expect(newHand, contains(topCard));

      final newDeck = newData['deck'] as List;
      expect(newDeck.length, 41);
    });

    // -----------------------------------------------------------------
    // applyAction — END_TURN
    // -----------------------------------------------------------------

    test('END_TURN advances to next player', () {
      final state = rules.createInitialGameState(_lobbyState());

      final newState = rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );

      // p2 should now be active
      expect(newState.turnState!.activePlayerId, 'p2');
    });

    test('END_TURN wraps around and increments round', () {
      var state = rules.createInitialGameState(_lobbyState());

      // p1 ends turn → p2 active
      state = rules.applyAction(
        state, 'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );
      expect(state.turnState!.activePlayerId, 'p2');

      // p2 ends turn → p1 active, new round
      state = rules.applyAction(
        state, 'p2',
        PlayerAction(playerId: 'p2', type: 'END_TURN', data: {}),
      );
      expect(state.turnState!.activePlayerId, 'p1');
      expect(state.turnState!.round, 2);
    });

    // -----------------------------------------------------------------
    // checkGameEnd
    // -----------------------------------------------------------------

    test('game not ended at start', () {
      final state = rules.createInitialGameState(_lobbyState());
      final result = rules.checkGameEnd(state);
      expect(result.ended, false);
    });

    test('game ends when deck is empty', () {
      var state = rules.createInitialGameState(_lobbyState());

      // Manually empty the deck
      final data = Map<String, dynamic>.from(state.gameState!.data);
      data['deck'] = <String>[];
      state = state.copyWith(
        gameState: state.gameState!.copyWith(data: data),
      );

      final result = rules.checkGameEnd(state);
      expect(result.ended, true);
    });

    // -----------------------------------------------------------------
    // buildBoardView
    // -----------------------------------------------------------------

    test('boardView contains scores and deckRemaining', () {
      final state = rules.createInitialGameState(_lobbyState());
      final view = rules.buildBoardView(state);

      expect(view.scores['p1'], 0);
      expect(view.scores['p2'], 0);
      expect(view.deckRemaining, 42);
      expect(view.data['packId'], 'simple_card_game');
    });

    // -----------------------------------------------------------------
    // buildPlayerView
    // -----------------------------------------------------------------

    test('playerView contains only own hand', () {
      final state = rules.createInitialGameState(_lobbyState());
      final p1View = rules.buildPlayerView(state, 'p1');
      final p2View = rules.buildPlayerView(state, 'p2');

      expect(p1View.hand.length, 5);
      expect(p2View.hand.length, 5);
      expect(p1View.playerId, 'p1');
      expect(p2View.playerId, 'p2');

      // Hands should not overlap
      for (final card in p1View.hand) {
        expect(p2View.hand, isNot(contains(card)));
      }

      // Active player has actions, non-active doesn't
      expect(p1View.allowedActions, isNotEmpty);
      expect(p2View.allowedActions, isEmpty);
    });

    // -----------------------------------------------------------------
    // Full game flow
    // -----------------------------------------------------------------

    test('play a few rounds end-to-end', () {
      var state = rules.createInitialGameState(_lobbyState());

      // Round 1: p1 plays a card, then ends turn
      final p1Card = (state.gameState!.data['hands'] as Map)['p1'][0] as String;
      state = rules.applyAction(state, 'p1',
          PlayerAction(playerId: 'p1', type: 'PLAY_CARD', data: {'cardId': p1Card}));
      expect((state.gameState!.data['scores'] as Map)['p1'], 1);

      state = rules.applyAction(state, 'p1',
          PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}));
      expect(state.turnState!.activePlayerId, 'p2');

      // Round 1: p2 draws a card, then ends turn
      state = rules.applyAction(state, 'p2',
          PlayerAction(playerId: 'p2', type: 'DRAW_CARD', data: {}));
      expect(((state.gameState!.data['hands'] as Map)['p2'] as List).length, 6);

      state = rules.applyAction(state, 'p2',
          PlayerAction(playerId: 'p2', type: 'END_TURN', data: {}));
      expect(state.turnState!.activePlayerId, 'p1');
      expect(state.turnState!.round, 2);

      // Game should still be ongoing
      expect(rules.checkGameEnd(state).ended, false);
    });
  });
}
