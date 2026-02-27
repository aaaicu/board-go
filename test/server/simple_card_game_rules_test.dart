import 'package:test/test.dart';

import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/player_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';
import '../../lib/shared/game_session/turn_state.dart';
import '../../lib/shared/game_session/turn_step.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/game_pack/packs/simple_card_game_rules.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal lobby-phase [GameSessionState] for two players.
GameSessionState _lobbyState({
  List<String> playerOrder = const ['p1', 'p2'],
}) {
  final players = {
    for (final id in playerOrder)
      id: PlayerSessionState(
        playerId: id,
        nickname: id,
        isConnected: true,
        isReady: true,
        reconnectToken: 'token-$id',
      ),
  };
  return GameSessionState(
    sessionId: 'test-session',
    phase: SessionPhase.lobby,
    players: players,
    playerOrder: playerOrder,
    version: 0,
    log: const [],
  );
}

/// Deterministic rules with a fixed deck seed for reproducible tests.
const _rules = SimpleCardGameRules(deckSeed: 42);

void main() {
  // ---------------------------------------------------------------------------
  // createInitialGameState
  // ---------------------------------------------------------------------------

  group('createInitialGameState', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test('transitions phase to inGame', () {
      expect(state.phase, equals(SessionPhase.inGame));
    });

    test('playerOrder matches the lobby state', () {
      expect(state.playerOrder, equals(['p1', 'p2']));
    });

    test('each player receives exactly 5 cards', () {
      final gameState = state.gameState!;
      final hands = gameState.data['hands'] as Map;
      expect((hands['p1'] as List).length, equals(5));
      expect((hands['p2'] as List).length, equals(5));
    });

    test('deck has 52 - 2*5 = 42 cards remaining', () {
      final gameState = state.gameState!;
      final deck = gameState.data['deck'] as List;
      expect(deck.length, equals(42));
    });

    test('turnState is initialised with round 1, turnIndex 0', () {
      final ts = state.turnState!;
      expect(ts.round, equals(1));
      expect(ts.turnIndex, equals(0));
      expect(ts.activePlayerId, equals('p1'));
      expect(ts.actionCountThisTurn, equals(0));
    });

    test('scores start at 0 for all players', () {
      final gameState = state.gameState!;
      final scores = gameState.data['scores'] as Map;
      expect(scores['p1'], equals(0));
      expect(scores['p2'], equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // buildPlayerView — privacy guarantee
  // ---------------------------------------------------------------------------

  group('buildPlayerView — hand privacy', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test("p1's view contains only p1's hand", () {
      final view = _rules.buildPlayerView(state, 'p1');
      expect(view.playerId, equals('p1'));
      expect(view.hand, isNotEmpty);

      // Cross-check: p1 hand must NOT contain any card from p2 hand.
      final hands = state.gameState!.data['hands'] as Map;
      final p2Hand = List<String>.from(hands['p2'] as List);

      for (final card in view.hand) {
        expect(p2Hand, isNot(contains(card)),
            reason: "p1's view must not expose p2's cards");
      }
    });

    test("p2's view contains only p2's hand", () {
      final view = _rules.buildPlayerView(state, 'p2');
      expect(view.playerId, equals('p2'));

      final hands = state.gameState!.data['hands'] as Map;
      final p1Hand = List<String>.from(hands['p1'] as List);

      for (final card in view.hand) {
        expect(p1Hand, isNot(contains(card)),
            reason: "p2's view must not expose p1's cards");
      }
    });

    test('hand in PlayerView equals the gameState hand exactly', () {
      final view = _rules.buildPlayerView(state, 'p1');
      final hands = state.gameState!.data['hands'] as Map;
      final p1Hand = List<String>.from(hands['p1'] as List);
      expect(view.hand, equals(p1Hand));
    });
  });

  // ---------------------------------------------------------------------------
  // buildBoardView — no hand data
  // ---------------------------------------------------------------------------

  group('buildBoardView', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test('contains deckRemaining = 42', () {
      final view = _rules.buildBoardView(state);
      expect(view.deckRemaining, equals(42));
    });

    test('contains scores for all players', () {
      final view = _rules.buildBoardView(state);
      expect(view.scores.containsKey('p1'), isTrue);
      expect(view.scores.containsKey('p2'), isTrue);
    });

    test('JSON serialisation does NOT include any hand data', () {
      final view = _rules.buildBoardView(state);
      final json = view.toJson();
      expect(json.containsKey('hands'), isFalse,
          reason: 'BoardView JSON must never include hands');
    });

    test('discardPile is empty at game start', () {
      final view = _rules.buildBoardView(state);
      expect(view.discardPile, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // getAllowedActions
  // ---------------------------------------------------------------------------

  group('getAllowedActions', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test('active player (p1) has PLAY_CARD, DRAW_CARD, END_TURN', () {
      final actions = _rules.getAllowedActions(state, 'p1');
      final types = actions.map((a) => a.actionType).toSet();
      expect(types, containsAll({'PLAY_CARD', 'DRAW_CARD', 'END_TURN'}));
    });

    test('non-active player (p2) has NO allowed actions', () {
      final actions = _rules.getAllowedActions(state, 'p2');
      expect(actions, isEmpty);
    });

    test('PLAY_CARD entries equal the number of cards in hand (5)', () {
      final actions = _rules.getAllowedActions(state, 'p1');
      final playCards = actions.where((a) => a.actionType == 'PLAY_CARD').toList();
      expect(playCards.length, equals(5));
    });

    test('returns empty list during lobby phase', () {
      final lobbyActions = _rules.getAllowedActions(_lobbyState(), 'p1');
      expect(lobbyActions, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // applyAction — PLAY_CARD
  // ---------------------------------------------------------------------------

  group('applyAction PLAY_CARD', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test('removes card from hand, adds to discard, scores +1', () {
      final hands = state.gameState!.data['hands'] as Map;
      final p1Hand = List<String>.from(hands['p1'] as List);
      final card = p1Hand.first;

      final action =
          PlayerAction(playerId: 'p1', type: 'PLAY_CARD', data: {'cardId': card});
      final next = _rules.applyAction(state, 'p1', action);

      final ng = next.gameState!;
      final newHand = List<String>.from((ng.data['hands'] as Map)['p1'] as List);
      final discard = List<String>.from(ng.data['discardPile'] as List);
      final scores = ng.data['scores'] as Map;

      expect(newHand, isNot(contains(card)));
      expect(discard, contains(card));
      expect(scores['p1'], equals(1));
    });

    test('does not mutate original state', () {
      final hands = state.gameState!.data['hands'] as Map;
      final originalHand = List<String>.from(hands['p1'] as List);
      final card = originalHand.first;

      _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'PLAY_CARD', data: {'cardId': card}),
      );

      // Original hand is unchanged.
      final handAfter =
          List<String>.from((state.gameState!.data['hands'] as Map)['p1'] as List);
      expect(handAfter, equals(originalHand));
    });

    test('version increments', () {
      final hands = state.gameState!.data['hands'] as Map;
      final card = (hands['p1'] as List).first as String;

      final next = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'PLAY_CARD', data: {'cardId': card}),
      );
      expect(next.version, greaterThan(state.version));
    });
  });

  // ---------------------------------------------------------------------------
  // applyAction — DRAW_CARD
  // ---------------------------------------------------------------------------

  group('applyAction DRAW_CARD', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test('hand grows by 1', () {
      final before = (state.gameState!.data['hands'] as Map)['p1'] as List;
      final next = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'DRAW_CARD', data: {}),
      );
      final after = (next.gameState!.data['hands'] as Map)['p1'] as List;
      expect(after.length, equals(before.length + 1));
    });

    test('deck shrinks by 1', () {
      final deckBefore = (state.gameState!.data['deck'] as List).length;
      final next = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'DRAW_CARD', data: {}),
      );
      final deckAfter = (next.gameState!.data['deck'] as List).length;
      expect(deckAfter, equals(deckBefore - 1));
    });
  });

  // ---------------------------------------------------------------------------
  // applyAction — END_TURN
  // ---------------------------------------------------------------------------

  group('applyAction END_TURN', () {
    late GameSessionState state;

    setUp(() {
      state = _rules.createInitialGameState(_lobbyState());
    });

    test('advances activePlayerId to p2', () {
      final next = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );
      expect(next.turnState!.activePlayerId, equals('p2'));
    });

    test('advances turnIndex to 1', () {
      final next = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );
      expect(next.turnState!.turnIndex, equals(1));
    });

    test('wraps around back to p1 after p2 ends turn', () {
      var s = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );
      s = _rules.applyAction(
        s,
        'p2',
        PlayerAction(playerId: 'p2', type: 'END_TURN', data: {}),
      );
      expect(s.turnState!.activePlayerId, equals('p1'));
    });

    test('increments round after all players complete their turn', () {
      var s = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );
      s = _rules.applyAction(
        s,
        'p2',
        PlayerAction(playerId: 'p2', type: 'END_TURN', data: {}),
      );
      expect(s.turnState!.round, equals(2));
    });

    test('resets actionCountThisTurn to 0', () {
      final next = _rules.applyAction(
        state,
        'p1',
        PlayerAction(playerId: 'p1', type: 'END_TURN', data: {}),
      );
      expect(next.turnState!.actionCountThisTurn, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // checkGameEnd
  // ---------------------------------------------------------------------------

  group('checkGameEnd', () {
    test('returns ended=false when deck is non-empty and rounds < max', () {
      final state = _rules.createInitialGameState(_lobbyState());
      final result = _rules.checkGameEnd(state);
      expect(result.ended, isFalse);
    });

    test('returns ended=true when deck is exhausted', () {
      var state = _rules.createInitialGameState(_lobbyState());
      final gs = state.gameState!;
      state = state.copyWith(
        gameState: gs.copyWith(data: {...gs.data, 'deck': <String>[]}),
      );
      expect(_rules.checkGameEnd(state).ended, isTrue);
    });

    test('returns ended=true when round exceeds maximum (3)', () {
      var state = _rules.createInitialGameState(_lobbyState());
      state = state.copyWith(turnState: state.turnState!.copyWith(round: 4));
      expect(_rules.checkGameEnd(state).ended, isTrue);
    });

    test('winner is player with highest score', () {
      var state = _rules.createInitialGameState(_lobbyState());
      final gs = state.gameState!;
      state = state.copyWith(
        gameState: gs.copyWith(
          data: {
            ...gs.data,
            'deck': <String>[],
            'scores': {'p1': 3, 'p2': 7},
          },
        ),
      );
      final result = _rules.checkGameEnd(state);
      expect(result.ended, isTrue);
      expect(result.winnerIds, equals(['p2']));
    });

    test('tie returns all tied players as winners', () {
      var state = _rules.createInitialGameState(_lobbyState());
      final gs = state.gameState!;
      state = state.copyWith(
        gameState: gs.copyWith(
          data: {
            ...gs.data,
            'deck': <String>[],
            'scores': {'p1': 5, 'p2': 5},
          },
        ),
      );
      final result = _rules.checkGameEnd(state);
      expect(result.ended, isTrue);
      expect(result.winnerIds, containsAll(['p1', 'p2']));
    });
  });

  // ---------------------------------------------------------------------------
  // JSON round-trip for new types
  // ---------------------------------------------------------------------------

  group('JSON round-trip', () {
    test('TurnState serialises and deserialises correctly', () {
      const ts = TurnState(
        round: 2,
        turnIndex: 1,
        activePlayerId: 'p2',
        step: TurnStep.main,
        actionCountThisTurn: 3,
      );
      final restored = TurnState.fromJson(ts.toJson());
      expect(restored.round, equals(ts.round));
      expect(restored.turnIndex, equals(ts.turnIndex));
      expect(restored.activePlayerId, equals(ts.activePlayerId));
      expect(restored.step, equals(ts.step));
      expect(restored.actionCountThisTurn, equals(ts.actionCountThisTurn));
    });

    test('GameSessionState with turnState and gameState round-trips', () {
      final state = _rules.createInitialGameState(_lobbyState());
      final restored = GameSessionState.fromJson(state.toJson());
      expect(restored.phase, equals(state.phase));
      expect(restored.turnState!.round, equals(state.turnState!.round));
      expect(restored.turnState!.activePlayerId,
          equals(state.turnState!.activePlayerId));
    });
  });
}
