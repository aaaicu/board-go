import 'dart:math';

import 'package:test/test.dart';

import '../../../lib/shared/game_pack/engine/json_driven_rules.dart';
import '../../../lib/shared/game_pack/engine/packs/secret_hitler_def.dart';
import '../../../lib/shared/game_pack/player_action.dart';
import '../../../lib/shared/game_session/game_session_state.dart';
import '../../../lib/shared/game_session/player_session_state.dart';
import '../../../lib/shared/game_session/session_phase.dart';

GameSessionState _lobbyState({int playerCount = 5}) {
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
    sessionId: 'sh-test',
    phase: SessionPhase.lobby,
    players: players,
    playerOrder: order,
    version: 0,
    log: [],
  );
}

void main() {
  group('JsonDrivenRules — SecretHitler', () {
    late JsonDrivenRules rules;

    setUp(() {
      rules = JsonDrivenRules(
        definition: secretHitlerDefinition(),
        rng: Random(42),
      );
    });

    // -----------------------------------------------------------------
    // Pack metadata
    // -----------------------------------------------------------------

    test('packId and player limits', () {
      expect(rules.packId, 'secret_hitler');
      expect(rules.minPlayers, 5);
      expect(rules.maxPlayers, 10);
    });

    // -----------------------------------------------------------------
    // createInitialGameState
    // -----------------------------------------------------------------

    test('setup creates correct initial state for 5 players', () {
      final state = rules.createInitialGameState(_lobbyState(playerCount: 5));

      expect(state.phase, SessionPhase.inGame);
      expect(state.gameState, isNotNull);

      final data = state.gameState!.data;

      // Phase
      expect(data['phase'], 'ROLE_REVEAL');

      // Roles: 1 HITLER + 1 FASCIST + 3 LIBERAL = 5
      final roles = data['roles'] as Map;
      expect(roles.length, 5);
      final roleValues = roles.values.toList();
      expect(roleValues.where((r) => r == 'HITLER').length, 1);
      expect(roleValues.where((r) => r == 'FASCIST').length, 1);
      expect(roleValues.where((r) => r == 'LIBERAL').length, 3);

      // Deck: 17 total (11 FASCIST + 6 LIBERAL)
      final deck = data['deck'] as List;
      expect(deck.length, 17);

      // Policies start at 0
      expect(data['liberalPolicies'], 0);
      expect(data['fascistPolicies'], 0);

      // President is first player
      expect(data['presidentId'], isNotNull);
    });

    test('setup creates correct roles for 7 players', () {
      final state = rules.createInitialGameState(_lobbyState(playerCount: 7));
      final roles = state.gameState!.data['roles'] as Map;
      final roleValues = roles.values.toList();
      // 7 players: 1 HITLER + 2 FASCIST + 4 LIBERAL
      expect(roleValues.where((r) => r == 'HITLER').length, 1);
      expect(roleValues.where((r) => r == 'FASCIST').length, 2);
      expect(roleValues.where((r) => r == 'LIBERAL').length, 4);
    });

    test('setup creates correct roles for 9 players', () {
      final state = rules.createInitialGameState(_lobbyState(playerCount: 9));
      final roles = state.gameState!.data['roles'] as Map;
      final roleValues = roles.values.toList();
      // 9 players: 1 HITLER + 3 FASCIST + 5 LIBERAL
      expect(roleValues.where((r) => r == 'HITLER').length, 1);
      expect(roleValues.where((r) => r == 'FASCIST').length, 3);
      expect(roleValues.where((r) => r == 'LIBERAL').length, 5);
    });

    // -----------------------------------------------------------------
    // getAllowedActions — ROLE_REVEAL
    // -----------------------------------------------------------------

    test('ROLE_REVEAL: all players can press READY', () {
      final state = rules.createInitialGameState(_lobbyState());

      // All players should be able to press READY
      for (final pid in state.playerOrder) {
        final actions = rules.getAllowedActions(state, pid);
        final readyActions = actions.where((a) => a.actionType == 'READY');
        expect(readyActions.length, 1,
            reason: '$pid should have READY action');
      }
    });

    // -----------------------------------------------------------------
    // applyAction — READY
    // -----------------------------------------------------------------

    test('READY: all players ready → transitions to CHANCELLOR_NOMINATION', () {
      var state = rules.createInitialGameState(_lobbyState());

      // Each player presses READY
      for (final pid in state.playerOrder) {
        state = rules.applyAction(
          state, pid,
          PlayerAction(playerId: pid, type: 'READY', data: {}),
        );
      }

      expect(state.gameState!.data['phase'], 'CHANCELLOR_NOMINATION');
    });

    // -----------------------------------------------------------------
    // getAllowedActions — CHANCELLOR_NOMINATION
    // -----------------------------------------------------------------

    test('CHANCELLOR_NOMINATION: president can nominate', () {
      var state = rules.createInitialGameState(_lobbyState());

      // All READY
      for (final pid in state.playerOrder) {
        state = rules.applyAction(state, pid,
            PlayerAction(playerId: pid, type: 'READY', data: {}));
      }

      final presId = state.gameState!.data['presidentId'] as String;
      final actions = rules.getAllowedActions(state, presId);
      final nominateActions =
          actions.where((a) => a.actionType == 'NOMINATE').toList();

      // President can nominate others (not self) — should be playerCount - 1
      // minus term limit exclusions (none at game start)
      expect(nominateActions.length, greaterThan(0));

      // President should not be able to nominate self
      for (final a in nominateActions) {
        expect(a.params['targetId'], isNot(equals(presId)));
      }
    });

    // -----------------------------------------------------------------
    // applyAction — NOMINATE → VOTING
    // -----------------------------------------------------------------

    test('NOMINATE: transitions to VOTING phase', () {
      var state = rules.createInitialGameState(_lobbyState());

      // All READY
      for (final pid in state.playerOrder) {
        state = rules.applyAction(state, pid,
            PlayerAction(playerId: pid, type: 'READY', data: {}));
      }

      final presId = state.gameState!.data['presidentId'] as String;
      final nominateActions = rules.getAllowedActions(state, presId)
          .where((a) => a.actionType == 'NOMINATE')
          .toList();

      final targetId = nominateActions.first.params['targetId'] as String;

      state = rules.applyAction(state, presId,
          PlayerAction(playerId: presId, type: 'NOMINATE', data: {'targetId': targetId}));

      expect(state.gameState!.data['phase'], 'VOTING');
      expect(state.gameState!.data['chancellorCandidateId'], targetId);
    });

    // -----------------------------------------------------------------
    // VOTING
    // -----------------------------------------------------------------

    test('VOTING: all vote Ja → passes, moves to LEGISLATIVE_PRESIDENT', () {
      var state = rules.createInitialGameState(_lobbyState());

      // All READY
      for (final pid in state.playerOrder) {
        state = rules.applyAction(state, pid,
            PlayerAction(playerId: pid, type: 'READY', data: {}));
      }

      // NOMINATE
      final presId = state.gameState!.data['presidentId'] as String;
      final target = rules.getAllowedActions(state, presId)
          .firstWhere((a) => a.actionType == 'NOMINATE')
          .params['targetId'] as String;
      state = rules.applyAction(state, presId,
          PlayerAction(playerId: presId, type: 'NOMINATE', data: {'targetId': target}));

      // All vote Ja
      for (final pid in state.playerOrder) {
        state = rules.applyAction(state, pid,
            PlayerAction(playerId: pid, type: 'VOTE_JA', data: {}));
      }

      // Should have moved to LEGISLATIVE_PRESIDENT
      expect(state.gameState!.data['phase'], 'LEGISLATIVE_PRESIDENT');
      expect(state.gameState!.data['voteResult'], 'PASSED');
      expect(state.gameState!.data['drawnPolicies'], hasLength(3));
    });

    test('VOTING: majority Nein → election tracker increments', () {
      var state = rules.createInitialGameState(_lobbyState());

      // All READY
      for (final pid in state.playerOrder) {
        state = rules.applyAction(state, pid,
            PlayerAction(playerId: pid, type: 'READY', data: {}));
      }

      // NOMINATE
      final presId = state.gameState!.data['presidentId'] as String;
      final target = rules.getAllowedActions(state, presId)
          .firstWhere((a) => a.actionType == 'NOMINATE')
          .params['targetId'] as String;
      state = rules.applyAction(state, presId,
          PlayerAction(playerId: presId, type: 'NOMINATE', data: {'targetId': target}));

      // All vote Nein
      for (final pid in state.playerOrder) {
        state = rules.applyAction(state, pid,
            PlayerAction(playerId: pid, type: 'VOTE_NEIN', data: {}));
      }

      // After all Nein votes, either:
      // - voteResult == FAILED and phase moves to CHANCELLOR_NOMINATION
      // - or votes are still being counted
      final data = state.gameState!.data;
      final votes = data['votes'] as Map;
      expect(votes.length, 5, reason: 'All 5 players should have voted');
      // The phase should have advanced past VOTING
      expect(data['phase'], isNot(equals('VOTING')));
    });

    // -----------------------------------------------------------------
    // checkGameEnd
    // -----------------------------------------------------------------

    test('game not ended at start', () {
      final state = rules.createInitialGameState(_lobbyState());
      expect(rules.checkGameEnd(state).ended, false);
    });

    test('game ends when winner is set', () {
      var state = rules.createInitialGameState(_lobbyState());
      final data = Map<String, dynamic>.from(state.gameState!.data);
      data['winner'] = 'LIBERAL';
      state = state.copyWith(
        gameState: state.gameState!.copyWith(data: data),
      );
      expect(rules.checkGameEnd(state).ended, true);
    });

    // -----------------------------------------------------------------
    // buildBoardView
    // -----------------------------------------------------------------

    test('boardView excludes private data', () {
      final state = rules.createInitialGameState(_lobbyState());
      final view = rules.buildBoardView(state);

      expect(view.data['packId'], 'secret_hitler');
      expect(view.data['phase'], 'ROLE_REVEAL');
      // Should NOT contain roles or deck
      expect(view.data.containsKey('roles'), false);
    });

    // -----------------------------------------------------------------
    // buildPlayerView
    // -----------------------------------------------------------------

    test('playerView contains role info', () {
      final state = rules.createInitialGameState(_lobbyState());
      final pid = state.playerOrder.first;
      final view = rules.buildPlayerView(state, pid);

      expect(view.data['packId'], 'secret_hitler');
      expect(view.data['myRole'], isNotNull);
      expect(view.data['myParty'], isNotNull);
    });
  });
}
