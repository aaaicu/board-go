import 'dart:math';

import 'package:test/test.dart';

import '../../../lib/shared/game_pack/engine/json_driven_rules.dart';
import '../../../lib/shared/game_pack/engine/packs/stockpile_def.dart';
import '../../../lib/shared/game_pack/player_action.dart';
import '../../../lib/shared/game_session/game_session_state.dart';
import '../../../lib/shared/game_session/player_session_state.dart';
import '../../../lib/shared/game_session/session_phase.dart';

GameSessionState _lobbyState({int playerCount = 3}) {
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
    sessionId: 'sp-test',
    phase: SessionPhase.lobby,
    players: players,
    playerOrder: order,
    version: 0,
    log: [],
  );
}

void main() {
  group('JsonDrivenRules — Stockpile', () {
    late JsonDrivenRules rules;

    setUp(() {
      rules = JsonDrivenRules(
        definition: stockpileDefinition(),
        rng: Random(42),
      );
    });

    // ─── Pack metadata ────────────────────────────────────────────────

    test('packId and player limits', () {
      expect(rules.packId, 'stockpile');
      expect(rules.minPlayers, 3);
      expect(rules.maxPlayers, 5);
    });

    // ─── createInitialGameState ───────────────────────────────────────

    test('setup creates correct initial state for 3 players', () {
      final state = rules.createInitialGameState(_lobbyState(playerCount: 3));

      expect(state.phase, SessionPhase.inGame);
      expect(state.gameState, isNotNull);

      final data = state.gameState!.data;

      expect(data['phase'], 'supply');
      expect(data['round'], 1);
      expect(data['totalRounds'], 8);

      // Stock prices all start at 5
      final prices = data['stockPrices'] as Map;
      expect(prices.length, 6);
      for (final p in prices.values) {
        expect(p, 5);
      }

      // Cash: 3 players × $20,000
      final cash = data['cash'] as Map;
      expect(cash.length, 3);
      for (final c in cash.values) {
        expect(c, 20000);
      }

      // Stockpiles: 3 (one per player), each with 1 face-up card
      final stockpiles = data['stockpiles'] as List;
      expect(stockpiles.length, 3);
      for (final sp in stockpiles) {
        final m = sp as Map;
        expect((m['faceUpCards'] as List).length, 1);
        expect((m['faceDownCards'] as List).length, 0);
        expect(m['currentBid'], 0);
        expect(m['currentBidderId'], isNull);
      }

      // Supply hands: 2 cards per player
      final supplyHands = data['supplyHands'] as Map;
      expect(supplyHands.length, 3);
      for (final hand in supplyHands.values) {
        expect((hand as List).length, 2);
      }

      // Market deck: 80 - 3 (stockpiles) - 6 (supply 2×3) = 71
      final deck = data['marketDeck'] as List;
      expect(deck.length, 71);

      // Forecasts generated
      final forecastCompanies = data['forecastCompanies'] as List;
      final forecastChanges = data['forecastChanges'] as List;
      expect(forecastCompanies.length, 8); // totalRounds
      expect(forecastChanges.length, 8);
      // Each round has 6 forecasts
      for (final fc in forecastCompanies) {
        expect((fc as List).length, 6);
      }
    });

    test('setup creates correct totalRounds for 4 players', () {
      final state = rules.createInitialGameState(_lobbyState(playerCount: 4));
      expect(state.gameState!.data['totalRounds'], 6);
    });

    test('setup creates correct totalRounds for 5 players', () {
      final state = rules.createInitialGameState(_lobbyState(playerCount: 5));
      expect(state.gameState!.data['totalRounds'], 4);
    });

    // ─── getAllowedActions — supply ───────────────────────────────────

    test('supply: active player can place face-up and face-down', () {
      final state = rules.createInitialGameState(_lobbyState());
      final activeId = state.gameState!.activePlayerId;
      final actions = rules.getAllowedActions(state, activeId!);

      final faceUpActions =
          actions.where((a) => a.actionType == 'PLACE_FACE_UP').toList();
      final faceDownActions =
          actions.where((a) => a.actionType == 'PLACE_FACE_DOWN').toList();

      // 2 cards × 3 stockpiles = 6 options each
      expect(faceUpActions.length, 6);
      expect(faceDownActions.length, 6);

      // Non-active player has no actions
      final otherIds =
          state.playerOrder.where((id) => id != activeId).toList();
      for (final oid in otherIds) {
        expect(rules.getAllowedActions(state, oid), isEmpty);
      }
    });

    test('supply: placing face-up reduces options', () {
      var state = rules.createInitialGameState(_lobbyState());
      final activeId = state.gameState!.activePlayerId!;

      // Place face-up
      final faceUpAction = rules
          .getAllowedActions(state, activeId)
          .firstWhere((a) => a.actionType == 'PLACE_FACE_UP');
      state = rules.applyAction(
        state,
        activeId,
        PlayerAction(
          playerId: activeId,
          type: 'PLACE_FACE_UP',
          data: Map<String, dynamic>.from(faceUpAction.params),
        ),
      );

      // After placing face-up, only face-down should be available
      final actions = rules.getAllowedActions(state, activeId);
      expect(actions.where((a) => a.actionType == 'PLACE_FACE_UP'), isEmpty);
      expect(
        actions.where((a) => a.actionType == 'PLACE_FACE_DOWN'),
        isNotEmpty,
      );
    });

    test('supply: placing both cards advances to next player', () {
      var state = rules.createInitialGameState(_lobbyState());
      final activeId = state.gameState!.activePlayerId!;

      // Place face-up
      var faceUp = rules
          .getAllowedActions(state, activeId)
          .firstWhere((a) => a.actionType == 'PLACE_FACE_UP');
      state = rules.applyAction(
        state,
        activeId,
        PlayerAction(
          playerId: activeId,
          type: 'PLACE_FACE_UP',
          data: Map<String, dynamic>.from(faceUp.params),
        ),
      );

      // Place face-down
      var faceDown = rules
          .getAllowedActions(state, activeId)
          .firstWhere((a) => a.actionType == 'PLACE_FACE_DOWN');
      state = rules.applyAction(
        state,
        activeId,
        PlayerAction(
          playerId: activeId,
          type: 'PLACE_FACE_DOWN',
          data: Map<String, dynamic>.from(faceDown.params),
        ),
      );

      // Active player should have changed
      final newActiveId = state.gameState!.activePlayerId;
      expect(newActiveId, isNot(equals(activeId)));
      expect(state.gameState!.data['phase'], 'supply');
    });

    // ─── Full supply phase → demand ──────────────────────────────────

    test('all players completing supply transitions to demand', () {
      var state = rules.createInitialGameState(_lobbyState());

      // Each player places face-up then face-down
      for (final pid in state.playerOrder) {
        final faceUp = rules
            .getAllowedActions(state, pid)
            .firstWhere((a) => a.actionType == 'PLACE_FACE_UP');
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'PLACE_FACE_UP',
            data: Map<String, dynamic>.from(faceUp.params),
          ),
        );

        final faceDown = rules
            .getAllowedActions(state, pid)
            .firstWhere((a) => a.actionType == 'PLACE_FACE_DOWN');
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'PLACE_FACE_DOWN',
            data: Map<String, dynamic>.from(faceDown.params),
          ),
        );
      }

      expect(state.gameState!.data['phase'], 'demand');
    });

    // ─── Demand phase ────────────────────────────────────────────────

    GameSessionState _enterDemand({int playerCount = 3}) {
      var state = rules.createInitialGameState(
        _lobbyState(playerCount: playerCount),
      );
      for (final pid in state.playerOrder) {
        final faceUp = rules
            .getAllowedActions(state, pid)
            .firstWhere((a) => a.actionType == 'PLACE_FACE_UP');
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'PLACE_FACE_UP',
            data: Map<String, dynamic>.from(faceUp.params),
          ),
        );
        final faceDown = rules
            .getAllowedActions(state, pid)
            .firstWhere((a) => a.actionType == 'PLACE_FACE_DOWN');
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'PLACE_FACE_DOWN',
            data: Map<String, dynamic>.from(faceDown.params),
          ),
        );
      }
      return state;
    }

    test('demand: active player can bid', () {
      final state = _enterDemand();
      final activeId = state.gameState!.activePlayerId!;
      final actions = rules.getAllowedActions(state, activeId);

      final bidActions =
          actions.where((a) => a.actionType == 'BID').toList();
      expect(bidActions, isNotEmpty);

      // Each bid has stockpileIndex and amount
      for (final bid in bidActions) {
        expect(bid.params.containsKey('stockpileIndex'), true);
        expect(bid.params.containsKey('amount'), true);
      }
    });

    test('demand: all players bid → transitions to action phase', () {
      var state = _enterDemand();

      // Each player bids on a different pile
      for (var i = 0; i < state.playerOrder.length; i++) {
        final pid = state.playerOrder[i];
        final actions = rules.getAllowedActions(state, pid);
        final bidActions =
            actions.where((a) => a.actionType == 'BID').toList();
        expect(bidActions, isNotEmpty,
            reason: '$pid should have BID actions');

        // Bid on pile i (or first available)
        final bid = bidActions.firstWhere(
          (a) => a.params['stockpileIndex'] == i,
          orElse: () => bidActions.first,
        );
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'BID',
            data: Map<String, dynamic>.from(bid.params),
          ),
        );
      }

      // Should have moved past demand
      final phase = state.gameState!.data['phase'] as String;
      expect(phase, 'action');
    });

    // ─── Action phase ────────────────────────────────────────────────

    test('action: player can skip with END_PHASE', () {
      var state = _enterDemand();

      // Quick bid: all on different piles
      for (var i = 0; i < state.playerOrder.length; i++) {
        final pid = state.playerOrder[i];
        final bid = rules
            .getAllowedActions(state, pid)
            .where((a) => a.actionType == 'BID')
            .firstWhere(
              (a) => a.params['stockpileIndex'] == i,
              orElse: () => rules
                  .getAllowedActions(state, pid)
                  .firstWhere((a) => a.actionType == 'BID'),
            );
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'BID',
            data: Map<String, dynamic>.from(bid.params),
          ),
        );
      }

      expect(state.gameState!.data['phase'], 'action');

      // All players END_PHASE to skip
      for (final pid in state.playerOrder) {
        final actions = rules.getAllowedActions(state, pid);
        final endPhase =
            actions.firstWhere((a) => a.actionType == 'END_PHASE');
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(playerId: pid, type: 'END_PHASE', data: {}),
        );
      }

      expect(state.gameState!.data['phase'], 'selling');
    });

    // ─── Selling phase → Movement → Next round ──────────────────────

    test('selling: all skip → movement → next round', () {
      var state = _enterDemand();

      // Quick bid all on different piles
      for (var i = 0; i < state.playerOrder.length; i++) {
        final pid = state.playerOrder[i];
        final bid = rules
            .getAllowedActions(state, pid)
            .where((a) => a.actionType == 'BID')
            .firstWhere(
              (a) => a.params['stockpileIndex'] == i,
              orElse: () => rules
                  .getAllowedActions(state, pid)
                  .firstWhere((a) => a.actionType == 'BID'),
            );
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(
            playerId: pid,
            type: 'BID',
            data: Map<String, dynamic>.from(bid.params),
          ),
        );
      }

      // Skip action phase
      for (final pid in state.playerOrder) {
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(playerId: pid, type: 'END_PHASE', data: {}),
        );
      }

      // Skip selling phase
      for (final pid in state.playerOrder) {
        state = rules.applyAction(
          state,
          pid,
          PlayerAction(playerId: pid, type: 'END_PHASE', data: {}),
        );
      }

      // Should have advanced to round 2, back to supply
      final data = state.gameState!.data;
      expect(data['round'], 2);
      expect(data['phase'], 'supply');
    });

    // ─── checkGameEnd ────────────────────────────────────────────────

    test('game not ended at start', () {
      final state = rules.createInitialGameState(_lobbyState());
      expect(rules.checkGameEnd(state).ended, false);
    });

    test('game ends when round exceeds totalRounds', () {
      var state = rules.createInitialGameState(_lobbyState());
      // Manually set round past totalRounds
      final data = Map<String, dynamic>.from(state.gameState!.data);
      data['round'] = (data['totalRounds'] as int) + 1;
      state = state.copyWith(
        gameState: state.gameState!.copyWith(data: data),
      );
      final result = rules.checkGameEnd(state);
      expect(result.ended, true);
      expect(result.winnerIds, isNotEmpty);
    });

    // ─── Views ───────────────────────────────────────────────────────

    test('boardView contains public game state', () {
      final state = rules.createInitialGameState(_lobbyState());
      final view = rules.buildBoardView(state);

      expect(view.data['packId'], 'stockpile');
      expect(view.data['phase'], 'supply');
      expect(view.data['round'], 1);
    });

    test('playerView contains private data', () {
      final state = rules.createInitialGameState(_lobbyState());
      final pid = state.playerOrder.first;
      final view = rules.buildPlayerView(state, pid);

      expect(view.data['packId'], 'stockpile');
      expect(view.data['phase'], 'supply');
    });
  });
}
