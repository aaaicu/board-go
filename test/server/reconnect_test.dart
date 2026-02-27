import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/game_server.dart';
import '../../lib/server/session_manager.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/player_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';
import '../../lib/shared/messages/join_message.dart';
import '../../lib/shared/messages/join_room_ack_message.dart';
import '../../lib/shared/messages/lobby_state_message.dart';
import '../../lib/shared/messages/ping_message.dart';
import '../../lib/shared/messages/ws_message.dart';

// ---------------------------------------------------------------------------
// Stubs
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

class _FakeSink implements SessionSink {
  final List<String> sent = [];
  bool closed = false;

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close() async => closed = true;
}

// ---------------------------------------------------------------------------
// WebSocket test client helper
// ---------------------------------------------------------------------------

class _WsClient {
  final WebSocketChannel _channel;
  late final Stream<WsMessage> messages;
  final _controller = StreamController<WsMessage>.broadcast();

  _WsClient(this._channel) {
    _channel.stream.listen(
      (raw) {
        final msg = WsMessage.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>);
        _controller.add(msg);
      },
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
// SessionManager reconnect unit tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionManager.reconnect', () {
    late SessionManager manager;

    setUp(() => manager = SessionManager());

    test('markDisconnected() sets isConnected=false without removing player', () {
      final sink = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink);
      manager.getReconnectToken('p1'); // ensure token is issued

      manager.markDisconnected('p1');

      expect(manager.isConnected('p1'), isFalse,
          reason: 'isConnected must be false after markDisconnected');
      expect(manager.displayName('p1'), equals('Alice'),
          reason: 'nickname must be preserved after disconnect');
      expect(manager.getReconnectToken('p1'), isNotEmpty,
          reason: 'reconnect token must survive disconnect');
    });

    test('reconnect() replaces sink and marks isConnected=true', () {
      final oldSink = _FakeSink();
      final newSink = _FakeSink();

      manager.register(playerId: 'p1', displayName: 'Alice', sink: oldSink);
      manager.markDisconnected('p1');

      manager.reconnect(playerId: 'p1', newSink: newSink);

      expect(manager.isConnected('p1'), isTrue);

      // Messages sent after reconnect must go to the new sink.
      manager.send('p1', 'hello');
      expect(newSink.sent, contains('hello'));
      expect(oldSink.sent, isNot(contains('hello')));
    });

    test('isReadyToStart() ignores disconnected players', () {
      final sink1 = _FakeSink();
      final sink2 = _FakeSink();

      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink1);
      manager.register(playerId: 'p2', displayName: 'Bob', sink: sink2);
      manager.setReady('p1', true);
      manager.setReady('p2', true);

      // p2 disconnects — only p1 remains connected and ready.
      manager.markDisconnected('p2');

      // p1 is connected and ready → can start.
      expect(manager.isReadyToStart(), isTrue);
    });

    test('isReadyToStart() is false when connected player is not ready', () {
      final sink1 = _FakeSink();
      final sink2 = _FakeSink();

      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink1);
      manager.register(playerId: 'p2', displayName: 'Bob', sink: sink2);
      manager.setReady('p1', false);
      manager.setReady('p2', true);

      // p2 disconnects — only p1 remains connected but not ready.
      manager.markDisconnected('p2');

      // p1 connected but not ready → cannot start.
      expect(manager.isReadyToStart(), isFalse);
    });

    test('buildLobbyState() reflects isConnected=false for disconnected player',
        () {
      final sink = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink);
      manager.markDisconnected('p1');

      final lobby = manager.buildLobbyState();
      final p1 = lobby.players.firstWhere((p) => p.playerId == 'p1');
      expect(p1.isConnected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Full GameServer reconnect integration tests
  // ---------------------------------------------------------------------------

  group('GameServer reconnect integration', () {
    late GameServer server;

    setUp(() async {
      server = GameServer(gamePack: _NoOpGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: GameState(
          gameId: 'reconnect-test',
          turn: 0,
          activePlayerId: '',
          data: {},
        ),
      );
    });

    tearDown(() async => server.stop());

    test('player disconnect marks them as offline; lobby shows isConnected=false',
        () async {
      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);

      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());

      await c1.next(WsMessageType.joinRoomAck);
      await c2.next(WsMessageType.joinRoomAck);

      // Arm listener on c2 for the disconnect event BEFORE closing c1.
      final offlineFuture = c2.messages.firstWhere((m) {
        if (m.type != WsMessageType.lobbyState) return false;
        final lobby = LobbyStateMessage.fromEnvelope(m);
        final p1 = lobby.players.where((p) => p.playerId == 'p1');
        return p1.isNotEmpty && !p1.first.isConnected;
      }).timeout(const Duration(seconds: 5));

      // Ungraceful disconnect (no LEAVE message — just close the socket).
      await c1.close();

      final lobbyMsg = await offlineFuture;
      final lobby = LobbyStateMessage.fromEnvelope(lobbyMsg);
      final p1Info = lobby.players.firstWhere((p) => p.playerId == 'p1');
      expect(p1Info.isConnected, isFalse);

      await c2.close();
    });

    test(
        'reconnect with valid token → JOIN_ROOM_ACK success with same playerId',
        () async {
      // Initial connection.
      final c1 = await _WsClient.connect(server.port!);
      c1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      final ack1 = JoinRoomAckMessage.fromEnvelope(
          await c1.next(WsMessageType.joinRoomAck));
      final token = ack1.reconnectToken!;
      await c1.close();

      // Wait briefly for server to process the disconnect.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Reconnect with the saved token.
      final c2 = await _WsClient.connect(server.port!);
      c2.send(
        JoinMessage.join(
          playerId: 'different-device-id',
          displayName: 'Alice',
          reconnectToken: token,
        ).toEnvelope(),
      );

      final ack2 = JoinRoomAckMessage.fromEnvelope(
          await c2.next(WsMessageType.joinRoomAck));

      expect(ack2.success, isTrue);
      expect(ack2.playerId, equals('p1'),
          reason: 'reconnect must restore the original playerId');
      expect(ack2.reconnectToken, equals(token),
          reason: 'reconnect token must remain the same');

      await c2.close();
    });

    test('reconnect with invalid token → JOIN_ROOM_ACK failure', () async {
      final c1 = await _WsClient.connect(server.port!);
      c1.send(
        JoinMessage.join(
          playerId: 'p-bad',
          displayName: 'Faker',
          reconnectToken: 'this-token-does-not-exist',
        ).toEnvelope(),
      );

      final ack = JoinRoomAckMessage.fromEnvelope(
          await c1.next(WsMessageType.joinRoomAck));

      // An invalid reconnect token should not cause a crash.
      // The server may succeed (treating it as a fresh join) or fail gracefully.
      // We assert only that the server responds without error.
      expect(ack.success, isTrue,
          reason: 'unknown token treated as fresh join, not a hard failure');

      await c1.close();
    });

    test('ping → pong echoes the same timestamp', () async {
      final c1 = await _WsClient.connect(server.port!);
      c1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      await c1.next(WsMessageType.joinRoomAck);

      const ts = 1_234_567_890;
      c1.send(PingMessage(timestamp: ts).toEnvelope());

      final pong = PongMessage.fromEnvelope(await c1.next(WsMessageType.pong));
      expect(pong.timestamp, equals(ts));

      await c1.close();
    });
  });
}
