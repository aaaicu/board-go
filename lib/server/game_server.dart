import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../shared/game_pack/game_pack_interface.dart';
import '../shared/game_pack/game_state.dart';
import '../shared/game_pack/player_action.dart';
import '../shared/messages/action_message.dart';
import '../shared/messages/join_message.dart';
import '../shared/messages/state_update_message.dart';
import '../shared/messages/ws_message.dart';
import 'server_isolate.dart' show PlayerEvent;
import 'session_manager.dart';

/// Wraps a [WebSocketChannel] sink to implement [SessionSink].
class _ChannelSink implements SessionSink {
  final WebSocketChannel _channel;

  _ChannelSink(this._channel);

  @override
  void add(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}

/// Full WebSocket game server.
///
/// Handles player join/leave and game actions by delegating to a
/// [GamePackInterface] implementation.
///
/// When [eventPort] is provided, [PlayerEvent] messages are sent to it
/// whenever a player joins or leaves so the UI isolate can stay in sync.
class GameServer {
  final GamePackInterface gamePack;
  final SendPort? eventPort;
  final SessionManager _sessions = SessionManager();

  HttpServer? _httpServer;
  GameState? _gameState;

  GameServer({required this.gamePack, this.eventPort});

  int? get port => _httpServer?.port;
  bool get isRunning => _httpServer != null;

  Future<void> start({
    String host = '0.0.0.0',
    int port = 8080,
    required GameState initialState,
  }) async {
    _gameState = initialState;
    await gamePack.initialize(initialState);

    final router = Router();
    router.get('/ws', webSocketHandler(_handleConnection));

    _httpServer = await shelf_io.serve(
      const Pipeline().addHandler(router.call),
      host,
      port,
    );
  }

  Future<void> stop() async {
    await gamePack.dispose();
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  void _handleConnection(WebSocketChannel channel) {
    final sink = _ChannelSink(channel);

    channel.stream.listen(
      (raw) => _handleMessage(raw as String, sink),
      onError: (Object e) => channel.sink.close(),
      onDone: () {
        // If the client disconnects without sending a LEAVE, clean up.
        _cleanUpOrphan(sink);
      },
      cancelOnError: true,
    );
  }

  /// Tracks sink→playerId so we can clean up on unexpected disconnect.
  final Map<SessionSink, String> _sinkToPlayer = {};

  void _handleMessage(String raw, SessionSink sink) {
    late WsMessage msg;
    try {
      msg = WsMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _sendError(sink, 'Invalid message format');
      return;
    }

    switch (msg.type) {
      case WsMessageType.join:
        _handleJoin(JoinMessage.fromEnvelope(msg), sink);
      case WsMessageType.leave:
        _handleLeave(JoinMessage.fromEnvelope(msg));
      case WsMessageType.action:
        _handleAction(ActionMessage.fromEnvelope(msg), sink);
      default:
        _sendError(sink, 'Unexpected message type: ${msg.type}');
    }
  }

  void _handleJoin(JoinMessage join, SessionSink sink) {
    final displayName = join.displayName ?? join.playerId;
    _sessions.register(
      playerId: join.playerId,
      displayName: displayName,
      sink: sink,
    );
    _sinkToPlayer[sink] = join.playerId;

    // Notify the UI isolate.
    eventPort?.send(PlayerEvent(
      joined: true,
      playerId: join.playerId,
      displayName: displayName,
    ));

    // Send the current game state to the newly joined player.
    final state = _gameState;
    if (state != null) {
      sink.add(
        jsonEncode(
          StateUpdateMessage(state: state.toJson()).toEnvelope().toJson(),
        ),
      );
    }

    // Notify all other players.
    _sessions.broadcast(
      jsonEncode(
        WsMessage(
          type: WsMessageType.join,
          payload: {
            'playerId': join.playerId,
            'displayName': displayName,
          },
        ).toJson(),
      ),
      excludePlayerId: join.playerId,
    );
  }

  void _handleLeave(JoinMessage leave) {
    final displayName =
        _sessions.displayName(leave.playerId) ?? leave.playerId;
    _sessions.unregister(leave.playerId);
    _sinkToPlayer.removeWhere((_, id) => id == leave.playerId);

    // Notify the UI isolate.
    eventPort?.send(PlayerEvent(
      joined: false,
      playerId: leave.playerId,
      displayName: displayName,
    ));

    _sessions.broadcast(
      jsonEncode(
        WsMessage(
          type: WsMessageType.leave,
          payload: {'playerId': leave.playerId},
        ).toJson(),
      ),
    );
  }

  void _handleAction(ActionMessage action, SessionSink sink) {
    final state = _gameState;
    if (state == null) {
      _sendError(sink, 'Game not initialized');
      return;
    }

    final playerAction = PlayerAction(
      playerId: action.playerId,
      type: action.actionType,
      data: action.data,
    );

    if (!gamePack.validateAction(playerAction, state)) {
      _sendError(sink, 'Action rejected: ${action.actionType}');
      return;
    }

    _gameState = gamePack.processAction(playerAction, state);

    _sessions.broadcast(
      jsonEncode(
        StateUpdateMessage(
          state: _gameState!.toJson(),
          triggeredBy: action.playerId,
        ).toEnvelope().toJson(),
      ),
    );
  }

  void _sendError(SessionSink sink, String reason) {
    sink.add(
      jsonEncode(
        WsMessage(
          type: WsMessageType.error,
          payload: {'reason': reason},
        ).toJson(),
      ),
    );
  }

  void _cleanUpOrphan(SessionSink sink) {
    final playerId = _sinkToPlayer.remove(sink);
    if (playerId != null && _sessions.isConnected(playerId)) {
      final displayName = _sessions.displayName(playerId) ?? playerId;
      _sessions.unregister(playerId);

      // Notify the UI isolate.
      eventPort?.send(PlayerEvent(
        joined: false,
        playerId: playerId,
        displayName: displayName,
      ));

      _sessions.broadcast(
        jsonEncode(
          WsMessage(
            type: WsMessageType.leave,
            payload: {'playerId': playerId},
          ).toJson(),
        ),
      );
    }
  }
}
