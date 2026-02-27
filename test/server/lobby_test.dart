import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/game_server.dart';
import '../../lib/server/session_manager.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/messages/join_message.dart';
import '../../lib/shared/messages/join_room_ack_message.dart';
import '../../lib/shared/messages/lobby_state_message.dart';
import '../../lib/shared/messages/set_ready_message.dart';
import '../../lib/shared/messages/ws_message.dart';

// ---------------------------------------------------------------------------
// Stub helpers
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

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close() async {}
}

/// WebSocket test client.
///
/// [messages] is a *single* shared broadcast stream. It is subscribed
/// immediately on construction so no events are dropped between sends.
class _WsClient {
  final WebSocketChannel _channel;

  /// Shared broadcast stream — subscribed immediately so events aren't lost.
  late final Stream<WsMessage> messages;

  /// Collects ALL received messages in arrival order.
  final List<WsMessage> _received = [];
  final _controller = StreamController<WsMessage>.broadcast();

  _WsClient(this._channel) {
    // Subscribe immediately; fan out to the broadcast controller.
    _channel.stream.listen(
      (raw) {
        final msg = WsMessage.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>);
        _received.add(msg);
        _controller.add(msg);
      },
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

  /// Waits for the next message of [type] that arrives *after* this call.
  Future<WsMessage> nextMessage(WsMessageType type,
      {Duration timeout = const Duration(seconds: 5)}) {
    return messages
        .firstWhere((m) => m.type == type)
        .timeout(timeout);
  }

  Future<void> close() => _channel.sink.close();
}

// ---------------------------------------------------------------------------
// SessionManager unit tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionManager lobby extensions', () {
    late SessionManager manager;

    setUp(() => manager = SessionManager());

    test('setReady marks player as ready', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.setReady('p1', true);
      expect(manager.isReady('p1'), isTrue);
    });

    test('setReady to false marks player as not ready', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.setReady('p1', true);
      manager.setReady('p1', false);
      expect(manager.isReady('p1'), isFalse);
    });

    test('isReady is false by default after register', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      expect(manager.isReady('p1'), isFalse);
    });

    test('unregister clears ready state', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.setReady('p1', true);
      manager.unregister('p1');
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      expect(manager.isReady('p1'), isFalse);
    });

    test('getReconnectToken returns a stable token per player', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      final t1 = manager.getReconnectToken('p1');
      final t2 = manager.getReconnectToken('p1');
      expect(t1, equals(t2));
      expect(t1, isNotEmpty);
    });

    test('two different players get different reconnect tokens', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.register(playerId: 'p2', displayName: 'Bob', sink: _FakeSink());
      final t1 = manager.getReconnectToken('p1');
      final t2 = manager.getReconnectToken('p2');
      expect(t1, isNot(equals(t2)));
    });

    test('findPlayerByReconnectToken returns correct playerId', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      final token = manager.getReconnectToken('p1');
      expect(manager.findPlayerByReconnectToken(token), equals('p1'));
    });

    test('findPlayerByReconnectToken returns null for unknown token', () {
      expect(manager.findPlayerByReconnectToken('unknown-token'), isNull);
    });

    test('buildLobbyState reflects player ready states', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.register(playerId: 'p2', displayName: 'Bob', sink: _FakeSink());
      manager.setReady('p1', true);

      final lobby = manager.buildLobbyState();
      final p1 = lobby.players.firstWhere((p) => p.playerId == 'p1');
      final p2 = lobby.players.firstWhere((p) => p.playerId == 'p2');
      expect(p1.isReady, isTrue);
      expect(p2.isReady, isFalse);
    });

    test('isReadyToStart is true with 1 player when ready', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.setReady('p1', true);
      expect(manager.isReadyToStart(), isTrue);
    });

    test('isReadyToStart is false with 1 player when not ready', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      expect(manager.isReadyToStart(), isFalse);
    });

    test('isReadyToStart is false when 2 players but one not ready', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.register(playerId: 'p2', displayName: 'Bob', sink: _FakeSink());
      manager.setReady('p1', true);
      expect(manager.isReadyToStart(), isFalse);
    });

    test('isReadyToStart is true when 2 players both ready', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.register(playerId: 'p2', displayName: 'Bob', sink: _FakeSink());
      manager.setReady('p1', true);
      manager.setReady('p2', true);
      expect(manager.isReadyToStart(), isTrue);
    });

    test('buildLobbyState.canStart matches isReadyToStart', () {
      manager.register(playerId: 'p1', displayName: 'Alice', sink: _FakeSink());
      manager.register(playerId: 'p2', displayName: 'Bob', sink: _FakeSink());
      manager.setReady('p1', true);
      manager.setReady('p2', true);

      final lobby = manager.buildLobbyState();
      expect(lobby.canStart, isTrue);
    });
  });

  // --------------------------------------------------------------------------
  // Integration tests — full GameServer via real WebSocket
  // --------------------------------------------------------------------------

  group('GameServer lobby integration', () {
    late GameServer server;

    setUp(() async {
      server = GameServer(gamePack: _NoOpGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: GameState(
          gameId: 'lobby-test',
          turn: 0,
          activePlayerId: '',
          data: {},
        ),
      );
    });

    tearDown(() async => server.stop());

    test('JOIN → JOIN_ROOM_ACK success + reconnectToken issued', () async {
      final client = await _WsClient.connect(server.port!);

      client.send(
        JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope(),
      );

      final ack = await client
          .nextMessage(WsMessageType.joinRoomAck)
          .timeout(const Duration(seconds: 5));

      final parsed = JoinRoomAckMessage.fromEnvelope(ack);
      expect(parsed.success, isTrue);
      expect(parsed.playerId, equals('p1'));
      expect(parsed.reconnectToken, isNotNull);
      expect(parsed.reconnectToken, isNotEmpty);

      await client.close();
    });

    test('JOIN → LOBBY_STATE broadcast to all registered clients', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      // p2 joins first — wait until registered.
      client2.send(
          JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());
      await client2.nextMessage(WsMessageType.joinRoomAck);

      // Arm the listener on client2 BEFORE p1 joins so no events are missed.
      final lobbyFuture = client2.messages
          .firstWhere((m) {
            if (m.type != WsMessageType.lobbyState) return false;
            final l = LobbyStateMessage.fromEnvelope(m);
            return l.players.any((p) => p.playerId == 'p1');
          })
          .timeout(const Duration(seconds: 5));

      // p1 joins now.
      client1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());

      final lobbyMsg = await lobbyFuture;
      final lobby = LobbyStateMessage.fromEnvelope(lobbyMsg);
      expect(lobby.players.any((p) => p.playerId == 'p1'), isTrue);
      expect(lobby.players.any((p) => p.playerId == 'p2'), isTrue);

      await Future.wait([client1.close(), client2.close()]);
    });

    test('SET_READY → player marked ready, LOBBY_STATE broadcast', () async {
      final client = await _WsClient.connect(server.port!);

      client.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());

      await client.nextMessage(WsMessageType.joinRoomAck);

      // Arm the listener for the SET_READY LOBBY_STATE before sending.
      final readyLobbyFuture = client.messages
          .firstWhere((m) {
            if (m.type != WsMessageType.lobbyState) return false;
            final l = LobbyStateMessage.fromEnvelope(m);
            return l.players.any((p) => p.playerId == 'p1' && p.isReady);
          })
          .timeout(const Duration(seconds: 5));

      client.send(
          SetReadyMessage(playerId: 'p1', isReady: true).toEnvelope());

      final lobbyMsg = await readyLobbyFuture;
      final lobby = LobbyStateMessage.fromEnvelope(lobbyMsg);
      final p1 = lobby.players.firstWhere((p) => p.playerId == 'p1');
      expect(p1.isReady, isTrue);

      await client.close();
    });

    test('2 players both ready → canStart=true in LOBBY_STATE', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      // Both join.
      client1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      client2.send(
          JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());

      // Wait for both acks.
      await Future.wait([
        client1.nextMessage(WsMessageType.joinRoomAck),
        client2.nextMessage(WsMessageType.joinRoomAck),
      ]);

      // Arm canStart listener before sending SET_READY messages.
      final canStartFuture = client1.messages
          .firstWhere((m) {
            if (m.type != WsMessageType.lobbyState) return false;
            return LobbyStateMessage.fromEnvelope(m).canStart;
          })
          .timeout(const Duration(seconds: 5));

      client1.send(
          SetReadyMessage(playerId: 'p1', isReady: true).toEnvelope());
      client2.send(
          SetReadyMessage(playerId: 'p2', isReady: true).toEnvelope());

      final lobbyMsg = await canStartFuture;
      expect(LobbyStateMessage.fromEnvelope(lobbyMsg).canStart, isTrue);

      await Future.wait([client1.close(), client2.close()]);
    });

    test('1 player ready → canStart=false', () async {
      final client1 = await _WsClient.connect(server.port!);
      final client2 = await _WsClient.connect(server.port!);

      client1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      client2.send(
          JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());

      await Future.wait([
        client1.nextMessage(WsMessageType.joinRoomAck),
        client2.nextMessage(WsMessageType.joinRoomAck),
      ]);

      // Arm listener before sending SET_READY.
      final lobbyFuture = client1.messages
          .firstWhere((m) {
            if (m.type != WsMessageType.lobbyState) return false;
            final l = LobbyStateMessage.fromEnvelope(m);
            return l.players.any((p) => p.playerId == 'p1' && p.isReady);
          })
          .timeout(const Duration(seconds: 5));

      // Only p1 sends SET_READY.
      client1.send(
          SetReadyMessage(playerId: 'p1', isReady: true).toEnvelope());

      final lobbyMsg = await lobbyFuture;
      final lobby = LobbyStateMessage.fromEnvelope(lobbyMsg);
      expect(lobby.canStart, isFalse);

      await Future.wait([client1.close(), client2.close()]);
    });

    test('reconnectToken re-join → same playerId restored', () async {
      // First connection — obtain the reconnect token.
      final client1 = await _WsClient.connect(server.port!);

      client1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());

      final ack = await client1.nextMessage(WsMessageType.joinRoomAck);
      final token = JoinRoomAckMessage.fromEnvelope(ack).reconnectToken!;

      await client1.close();

      // Reconnect with the token — the playerId in the JOIN is irrelevant.
      final client2 = await _WsClient.connect(server.port!);

      client2.send(
        JoinMessage.join(
          playerId: 'ignored-id',
          displayName: 'Alice',
          reconnectToken: token,
        ).toEnvelope(),
      );

      final ack2 = await client2.nextMessage(WsMessageType.joinRoomAck);
      final parsed = JoinRoomAckMessage.fromEnvelope(ack2);
      expect(parsed.success, isTrue);
      expect(parsed.playerId, equals('p1'));

      await client2.close();
    });
  });
}
