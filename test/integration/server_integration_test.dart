import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/game_server.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/messages/ws_message.dart';
import '../../lib/shared/messages/action_message.dart';
import '../../lib/shared/messages/join_message.dart';
import '../../lib/shared/messages/state_update_message.dart';

/// Simple game pack that counts processed actions in the state.
class _CounterGamePack implements GamePackInterface {
  @override
  Future<void> initialize(GameState initialState) async {}

  @override
  bool validateAction(PlayerAction action, GameState currentState) {
    return action.type != 'REJECT';
  }

  @override
  GameState processAction(PlayerAction action, GameState currentState) {
    final count = (currentState.data['count'] as int? ?? 0) + 1;
    return currentState.copyWith(
      data: {...currentState.data, 'count': count, 'lastAction': action.type},
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Connects a WebSocket client to the test server and returns a helper
/// that sends/receives typed [WsMessage]s.
class _WsClient {
  final WebSocketChannel _channel;

  _WsClient(this._channel);

  static Future<_WsClient> connect(int port) async {
    final uri = Uri.parse('ws://localhost:$port/ws');
    final ch = WebSocketChannel.connect(uri);
    await ch.ready;
    return _WsClient(ch);
  }

  void send(WsMessage msg) =>
      _channel.sink.add(jsonEncode(msg.toJson()));

  Stream<WsMessage> get messages => _channel.stream.map(
        (raw) => WsMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>),
      );

  Future<void> close() => _channel.sink.close();
}

void main() {
  group('GameServer integration', () {
    late GameServer server;
    late GameState initialState;

    setUp(() async {
      initialState = GameState(
        gameId: 'test-game',
        turn: 0,
        activePlayerId: 'p1',
        data: {'count': 0},
      );
      server = GameServer(gamePack: _CounterGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: initialState,
      );
    });

    tearDown(() async {
      await server.stop();
    });

    test('server starts and assigns a port', () {
      expect(server.port, greaterThan(0));
    });

    test('player can join and receives welcome state update', () async {
      final client = await _WsClient.connect(server.port!);
      final msgs = client.messages.asBroadcastStream();

      // Send join message
      client.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );

      // Expect a STATE_UPDATE back with current game state
      final msg = await msgs
          .firstWhere((m) => m.type == WsMessageType.stateUpdate)
          .timeout(const Duration(seconds: 5));

      final update = StateUpdateMessage.fromEnvelope(msg);
      expect(update.state['gameId'], equals('test-game'));

      await client.close();
    });

    test('valid action is processed and broadcast to all players', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      final stream1 = client1.messages.asBroadcastStream();
      final stream2 = client2.messages.asBroadcastStream();

      // Both join
      client1.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );
      client2.send(
        JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope(),
      );

      // Wait for both welcome messages
      await Future.wait([
        stream1
            .firstWhere((m) => m.type == WsMessageType.stateUpdate)
            .timeout(const Duration(seconds: 5)),
        stream2
            .firstWhere((m) => m.type == WsMessageType.stateUpdate)
            .timeout(const Duration(seconds: 5)),
      ]);

      // p1 sends an action
      final actionFuture1 = stream1
          .firstWhere((m) => m.type == WsMessageType.stateUpdate)
          .timeout(const Duration(seconds: 5));
      final actionFuture2 = stream2
          .firstWhere((m) => m.type == WsMessageType.stateUpdate)
          .timeout(const Duration(seconds: 5));

      client1.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'PLAY_CARD',
          data: {'cardId': 'ace'},
        ).toEnvelope(),
      );

      final update1 = StateUpdateMessage.fromEnvelope(await actionFuture1);
      final update2 = StateUpdateMessage.fromEnvelope(await actionFuture2);

      // Both clients should see the updated count (nested under 'data')
      final data1 = update1.state['data'] as Map;
      final data2 = update2.state['data'] as Map;
      expect(data1['count'], equals(1));
      expect(data1['lastAction'], equals('PLAY_CARD'));
      expect(data2['count'], equals(1));

      await Future.wait([client1.close(), client2.close()]);
    });

    test('invalid action returns error message to the sender only', () async {
      final client = await _WsClient.connect(server.port!);
      final stream = client.messages.asBroadcastStream();

      client.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );
      await stream
          .firstWhere((m) => m.type == WsMessageType.stateUpdate)
          .timeout(const Duration(seconds: 5));

      client.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'REJECT',
          data: {},
        ).toEnvelope(),
      );

      final errorMsg = await stream
          .firstWhere((m) => m.type == WsMessageType.error)
          .timeout(const Duration(seconds: 5));

      expect(errorMsg.payload['reason'], isNotNull);

      await client.close();
    });

    test('player leave is broadcast to remaining players', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      final stream2 = client2.messages.asBroadcastStream();

      client1.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );
      client2.send(
        JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope(),
      );

      // Drain welcome messages
      await stream2
          .firstWhere((m) => m.type == WsMessageType.stateUpdate)
          .timeout(const Duration(seconds: 5));

      // p1 leaves
      client1.send(JoinMessage.leave(playerId: 'p1').toEnvelope());
      await client1.close();

      final leaveMsg = await stream2
          .firstWhere((m) => m.type == WsMessageType.leave)
          .timeout(const Duration(seconds: 5));

      expect(leaveMsg.payload['playerId'], equals('p1'));

      await client2.close();
    });
  });
}
