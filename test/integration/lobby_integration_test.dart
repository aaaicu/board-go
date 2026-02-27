import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/game_server.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/messages/join_message.dart';
import '../../lib/shared/messages/join_room_ack_message.dart';
import '../../lib/shared/messages/lobby_state_message.dart';
import '../../lib/shared/messages/set_ready_message.dart';
import '../../lib/shared/messages/ws_message.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _NoOpGamePack implements GamePackInterface {
  @override
  Future<void> initialize(GameState initialState) async {}
  @override
  bool validateAction(PlayerAction action, GameState currentState) => true;
  @override
  GameState processAction(PlayerAction action, GameState currentState) =>
      currentState;
  @override
  Future<void> dispose() async {}
}

/// WebSocket test client with a buffered, non-dropping broadcast stream.
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
    final ch = WebSocketChannel.connect(Uri.parse('ws://localhost:$port/ws'));
    await ch.ready;
    return _WsClient(ch);
  }

  void send(WsMessage msg) => _channel.sink.add(jsonEncode(msg.toJson()));

  Future<WsMessage> next(WsMessageType type,
      {Duration timeout = const Duration(seconds: 5)}) =>
      messages.firstWhere((m) => m.type == type).timeout(timeout);

  Future<void> close() => _channel.sink.close();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Lobby integration (full end-to-end)', () {
    late GameServer server;

    setUp(() async {
      server = GameServer(gamePack: _NoOpGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: GameState(
          gameId: 'lobby-e2e',
          turn: 0,
          activePlayerId: '',
          data: {},
        ),
      );
    });

    tearDown(() async => server.stop());

    test(
        'server starts → 2 clients connect → SET_READY x2 → '
        'LobbyState.canStart=true', () async {
      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);

      // Both join.
      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());

      // Both receive ACK with reconnect token.
      final ack1 = JoinRoomAckMessage.fromEnvelope(
          await c1.next(WsMessageType.joinRoomAck));
      final ack2 = JoinRoomAckMessage.fromEnvelope(
          await c2.next(WsMessageType.joinRoomAck));

      expect(ack1.success, isTrue);
      expect(ack2.success, isTrue);
      expect(ack1.reconnectToken, isNotNull);
      expect(ack2.reconnectToken, isNotNull);
      expect(ack1.reconnectToken, isNot(equals(ack2.reconnectToken)));

      // Arm the canStart listener BEFORE sending SET_READY.
      final canStartFuture = c1.messages
          .firstWhere((m) =>
              m.type == WsMessageType.lobbyState &&
              LobbyStateMessage.fromEnvelope(m).canStart)
          .timeout(const Duration(seconds: 5));

      // Both signal ready.
      c1.send(SetReadyMessage(playerId: 'p1', isReady: true).toEnvelope());
      c2.send(SetReadyMessage(playerId: 'p2', isReady: true).toEnvelope());

      final lobby = LobbyStateMessage.fromEnvelope(await canStartFuture);
      expect(lobby.canStart, isTrue);
      expect(lobby.players.length, equals(2));

      await Future.wait([c1.close(), c2.close()]);
    });

    test('reconnect flow: disconnect → reconnect with token → same playerId',
        () async {
      final c1 = await _WsClient.connect(server.port!);
      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());

      final ack = JoinRoomAckMessage.fromEnvelope(
          await c1.next(WsMessageType.joinRoomAck));
      final token = ack.reconnectToken!;

      await c1.close();

      // Reconnect with the token from a new connection.
      final c2 = await _WsClient.connect(server.port!);
      c2.send(
        JoinMessage.join(
          playerId: 'some-other-id',
          displayName: 'Alice',
          reconnectToken: token,
        ).toEnvelope(),
      );

      final ack2 = JoinRoomAckMessage.fromEnvelope(
          await c2.next(WsMessageType.joinRoomAck));

      expect(ack2.success, isTrue);
      expect(ack2.playerId, equals('p1'));

      await c2.close();
    });
  });
}
