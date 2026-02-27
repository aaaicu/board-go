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
import '../../lib/shared/messages/join_room_ack_message.dart';
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

/// Connects a WebSocket client to the test server.
/// Uses a buffered broadcast stream to avoid missing early messages.
class _WsClient {
  final WebSocketChannel _channel;
  late final Stream<WsMessage> messages;
  final _controller = StreamController<WsMessage>.broadcast();

  _WsClient(this._channel) {
    _channel.stream.listen(
      (raw) => _controller.add(
          WsMessage.fromJson(jsonDecode(raw as String) as Map<String, dynamic>)),
      onDone: _controller.close,
    );
    messages = _controller.stream;
  }

  static Future<_WsClient> connect(int port) async {
    final uri = Uri.parse('ws://localhost:$port/ws');
    final ch = WebSocketChannel.connect(uri);
    await ch.ready;
    return _WsClient(ch);
  }

  void send(WsMessage msg) => _channel.sink.add(jsonEncode(msg.toJson()));

  Future<WsMessage> next(WsMessageType type,
      {Duration timeout = const Duration(seconds: 5)}) =>
      messages.firstWhere((m) => m.type == type).timeout(timeout);

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

    test('player can join and receives JOIN_ROOM_ACK', () async {
      final client = await _WsClient.connect(server.port!);

      client.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );

      // Server now responds with JOIN_ROOM_ACK (not stateUpdate) in lobby phase.
      final ack = JoinRoomAckMessage.fromEnvelope(
          await client.next(WsMessageType.joinRoomAck));

      expect(ack.success, isTrue);
      expect(ack.playerId, equals('p1'));
      expect(ack.reconnectToken, isNotNull);

      await client.close();
    });

    test('valid action is processed and broadcast to all players', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      // Both join and wait for ACK.
      client1.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );
      client2.send(
        JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope(),
      );

      await Future.wait([
        client1.next(WsMessageType.joinRoomAck),
        client2.next(WsMessageType.joinRoomAck),
      ]);

      // Arm state-update listeners BEFORE sending the action.
      final actionFuture1 = client1.next(WsMessageType.stateUpdate);
      final actionFuture2 = client2.next(WsMessageType.stateUpdate);

      // p1 sends an action (session is still in lobby → goes through legacy path).
      client1.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'PLAY_CARD',
          data: {'cardId': 'ace'},
        ).toEnvelope(),
      );

      final update1 = StateUpdateMessage.fromEnvelope(await actionFuture1);
      final update2 = StateUpdateMessage.fromEnvelope(await actionFuture2);

      // Both clients should see the updated count (nested under 'data').
      final data1 = update1.state['data'] as Map;
      final data2 = update2.state['data'] as Map;
      expect(data1['count'], equals(1));
      expect(data1['lastAction'], equals('PLAY_CARD'));
      expect(data2['count'], equals(1));

      await Future.wait([client1.close(), client2.close()]);
    });

    test('invalid action returns error message to the sender only', () async {
      final client = await _WsClient.connect(server.port!);

      client.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );
      await client.next(WsMessageType.joinRoomAck);

      client.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'REJECT',
          data: {},
        ).toEnvelope(),
      );

      final errorMsg = await client.next(WsMessageType.error);
      expect(errorMsg.payload['reason'], isNotNull);

      await client.close();
    });

    test('player leave is broadcast to remaining players', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      client1.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );
      client2.send(
        JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope(),
      );

      // Wait for both ACKs.
      await Future.wait([
        client1.next(WsMessageType.joinRoomAck),
        client2.next(WsMessageType.joinRoomAck),
      ]);

      // Arm leave listener on client2 before p1 leaves.
      final leaveFuture = client2.next(WsMessageType.leave);

      // p1 leaves.
      client1.send(JoinMessage.leave(playerId: 'p1').toEnvelope());
      await client1.close();

      final leaveMsg = await leaveFuture;
      expect(leaveMsg.payload['playerId'], equals('p1'));

      await client2.close();
    });
  });
}
