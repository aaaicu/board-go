import 'package:test/test.dart';

import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';

/// A trivial [GamePackInterface] implementation used only in tests.
/// Tracks call history to verify the server calls the right methods.
class EchoGamePack implements GamePackInterface {
  final List<String> callLog = [];
  bool initialized = false;

  @override
  Future<void> initialize(GameState initialState) async {
    initialized = true;
    callLog.add('initialize');
  }

  @override
  GameState processAction(PlayerAction action, GameState currentState) {
    callLog.add('processAction:${action.type}');
    // Echo pack: copy the action data into state under "lastAction"
    return currentState.copyWith(
      data: {...currentState.data, 'lastAction': action.type},
    );
  }

  @override
  bool validateAction(PlayerAction action, GameState currentState) {
    callLog.add('validateAction:${action.type}');
    // Accept everything except actions with type "INVALID"
    return action.type != 'INVALID';
  }

  @override
  Future<void> dispose() async {
    callLog.add('dispose');
  }
}

void main() {
  group('GamePackInterface contract', () {
    late EchoGamePack pack;
    late GameState initialState;

    setUp(() {
      pack = EchoGamePack();
      initialState = GameState(
        gameId: 'game-1',
        turn: 0,
        activePlayerId: 'player-1',
        data: {},
      );
    });

    test('initialize is called with the initial state', () async {
      await pack.initialize(initialState);
      expect(pack.initialized, isTrue);
      expect(pack.callLog, contains('initialize'));
    });

    test('validateAction returns true for valid actions', () async {
      await pack.initialize(initialState);
      final action = PlayerAction(
        playerId: 'player-1',
        type: 'PLAY_CARD',
        data: {'cardId': 'ace'},
      );
      expect(pack.validateAction(action, initialState), isTrue);
    });

    test('validateAction returns false for invalid actions', () async {
      await pack.initialize(initialState);
      final action = PlayerAction(
        playerId: 'player-1',
        type: 'INVALID',
        data: {},
      );
      expect(pack.validateAction(action, initialState), isFalse);
    });

    test('processAction returns updated game state', () async {
      await pack.initialize(initialState);
      final action = PlayerAction(
        playerId: 'player-1',
        type: 'DRAW_CARD',
        data: {},
      );
      final newState = pack.processAction(action, initialState);
      expect(newState.data['lastAction'], equals('DRAW_CARD'));
    });

    test('processAction does not mutate the original state', () async {
      await pack.initialize(initialState);
      final action = PlayerAction(
        playerId: 'player-1',
        type: 'DRAW_CARD',
        data: {},
      );
      pack.processAction(action, initialState);
      expect(initialState.data, isEmpty);
    });

    test('dispose is called during teardown', () async {
      await pack.initialize(initialState);
      await pack.dispose();
      expect(pack.callLog.last, equals('dispose'));
    });
  });

  group('GameState', () {
    test('copyWith preserves unchanged fields', () {
      final state = GameState(
        gameId: 'g1',
        turn: 3,
        activePlayerId: 'p1',
        data: {'score': 10},
      );
      final copy = state.copyWith(turn: 4);
      expect(copy.gameId, equals('g1'));
      expect(copy.turn, equals(4));
      expect(copy.activePlayerId, equals('p1'));
      expect(copy.data['score'], equals(10));
    });

    test('toJson / fromJson round-trip', () {
      final state = GameState(
        gameId: 'g2',
        turn: 1,
        activePlayerId: 'p2',
        data: {'cards': 5},
      );
      final decoded = GameState.fromJson(state.toJson());
      expect(decoded.gameId, equals('g2'));
      expect(decoded.turn, equals(1));
      expect(decoded.activePlayerId, equals('p2'));
      expect(decoded.data['cards'], equals(5));
    });
  });

  group('PlayerAction', () {
    test('toJson / fromJson round-trip', () {
      final action = PlayerAction(
        playerId: 'p1',
        type: 'PLAY_CARD',
        data: {'cardId': 'king'},
      );
      final decoded = PlayerAction.fromJson(action.toJson());
      expect(decoded.playerId, equals('p1'));
      expect(decoded.type, equals('PLAY_CARD'));
      expect(decoded.data['cardId'], equals('king'));
    });
  });
}
