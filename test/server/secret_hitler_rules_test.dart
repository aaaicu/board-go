import 'package:board_go/shared/game_pack/packs/secret_hitler_rules.dart';
import 'package:board_go/shared/game_session/game_session_state.dart';
import 'package:board_go/shared/game_session/player_session_state.dart';
import 'package:board_go/shared/game_session/session_phase.dart';
import 'package:board_go/shared/game_pack/player_action.dart';
import 'package:test/test.dart';

void main() {
  group('SecretHitlerRules - Initialization', () {
    late SecretHitlerRules rules;
    late GameSessionState lobbyState;

    setUp(() {
      rules = SecretHitlerRules();
      lobbyState = const GameSessionState(
        sessionId: 'test_session',
        phase: SessionPhase.lobby,
        players: {
          'p1': PlayerSessionState(playerId: 'p1', nickname: 'Alice', isReady: true, isConnected: true, reconnectToken: '1'),
          'p2': PlayerSessionState(playerId: 'p2', nickname: 'Bob', isReady: true, isConnected: true, reconnectToken: '2'),
          'p3': PlayerSessionState(playerId: 'p3', nickname: 'Charlie', isReady: true, isConnected: true, reconnectToken: '3'),
          'p4': PlayerSessionState(playerId: 'p4', nickname: 'Dave', isReady: true, isConnected: true, reconnectToken: '4'),
          'p5': PlayerSessionState(playerId: 'p5', nickname: 'Eve', isReady: true, isConnected: true, reconnectToken: '5'),
        },
        playerOrder: ['p1', 'p2', 'p3', 'p4', 'p5'],
        version: 1,
        log: [],
      );
    });

    test('Initializes 5 player game correctly', () {
      final state = rules.createInitialGameState(lobbyState);
      
      expect(state.phase, equals(SessionPhase.inGame));
      expect(state.gameState, isNotNull);
      
      final data = state.gameState!.data;
      expect(data['phase'], equals('ROLE_REVEAL'));
      
      final roles = data['roles'] as Map<String, dynamic>;
      expect(roles.length, equals(5));
      
      int hitlerCount = 0;
      int fascistCount = 0;
      int liberalCount = 0;
      
      roles.values.forEach((role) {
        if (role == 'HITLER') hitlerCount++;
        if (role == 'FASCIST') fascistCount++;
        if (role == 'LIBERAL') liberalCount++;
      });
      
      expect(hitlerCount, equals(1));
      expect(fascistCount, equals(1), reason: '5 players: 1 Fascist');
      expect(liberalCount, equals(3), reason: '5 players: 3 Liberals');
      
      final deck = data['deck'] as List<String>;
      expect(deck.length, equals(17));
    });
    
    test('Role Reveal transitions to Nomination', () {
      var state = rules.createInitialGameState(lobbyState);
      for (int i = 1; i <= 5; i++) {
        state = rules.applyAction(
          state, 
          'p$i', 
          PlayerAction(playerId: 'p$i', type: 'READY', data: {})
        );
      }
      expect(state.gameState!.data['phase'], equals('CHANCELLOR_NOMINATION'));
    });
  });
}
