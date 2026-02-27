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
import '../shared/game_pack/game_pack_rules.dart';
import '../shared/game_pack/packs/simple_card_game_rules.dart';
import '../shared/game_pack/player_action.dart';
import '../shared/game_session/game_session_state.dart';
import '../shared/game_session/game_log_entry.dart';
import '../shared/game_session/player_session_state.dart';
import '../shared/game_session/session_phase.dart';
import '../shared/messages/action_message.dart';
import '../shared/messages/action_rejected_message.dart';
import '../shared/messages/board_view_message.dart';
import '../shared/messages/join_message.dart';
import '../shared/messages/join_room_ack_message.dart';
import '../shared/messages/ping_message.dart';
import '../shared/messages/player_view_message.dart';
import '../shared/messages/set_ready_message.dart';
import '../shared/messages/state_update_message.dart';
import '../shared/messages/ws_message.dart';
import 'game_state_store.dart';
import 'processed_actions_cache.dart';
import 'server_isolate.dart' show BoardViewEvent, LobbyStateEvent, PlayerEvent;
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
/// [GamePackInterface] implementation (legacy) and [GamePackRules] (Sprint 2).
///
/// Sprint 3 additions:
///   - Ping/pong heartbeat (client-driven).
///   - Proper disconnect handling via [SessionManager.markDisconnected] so
///     that disconnected players retain their seat.
///   - Optional [GameStateStore] for automatic persistence after every action.
///
/// When [eventPort] is provided, [PlayerEvent] messages are sent to it
/// whenever a player joins or leaves so the UI isolate can stay in sync.
class GameServer {
  final GamePackInterface gamePack;
  final SendPort? eventPort;

  /// Optional persistence store.  When null (default) state is not saved to
  /// disk — useful in tests to avoid database dependencies.
  final GameStateStore? _store;

  final SessionManager _sessions = SessionManager();

  HttpServer? _httpServer;
  GameState? _gameState;

  // ---------------------------------------------------------------------------
  // Sprint 2: session state + rules pipeline
  // ---------------------------------------------------------------------------

  /// The authoritative session state for Sprint 2 features.
  GameSessionState _sessionState = GameSessionState(
    sessionId: 'default',
    phase: SessionPhase.lobby,
    players: const {},
    playerOrder: const [],
    version: 0,
    log: const [],
  );

  /// Game-pack rules for the current session.  Defaults to [SimpleCardGameRules].
  GamePackRules _gamePackRules = const SimpleCardGameRules();

  /// Ring-buffer of recently processed [ActionMessage.clientActionId] values.
  /// Used to reject duplicate actions (idempotency).
  final ProcessedActionsCache _processedActions = ProcessedActionsCache();

  GameServer({
    required this.gamePack,
    this.eventPort,
    GameStateStore? store,
  }) : _store = store;

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

  // ---------------------------------------------------------------------------
  // Sprint 2: game start
  // ---------------------------------------------------------------------------

  /// Creates the [GamePackRules] instance for the given [packId].
  ///
  /// Uses a direct switch rather than [GamePackLoader] because the server runs
  /// in a Flutter Isolate where [rootBundle] availability is not guaranteed.
  /// [GamePackLoader] is used on the UI side (e.g. [LobbyScreen]) where the
  /// asset system is fully initialised.
  GamePackRules _createRulesForPack(String packId) {
    switch (packId) {
      case 'simple_card_battle':
      case 'simple_card_game':
      default:
        return const SimpleCardGameRules();
    }
  }

  /// Transitions the session from lobby to in-game.
  ///
  /// The optional [packId] selects which game-pack rules to use.
  /// Defaults to [SimpleCardGameRules] when omitted.
  ///
  /// Called by the server isolate when it receives a [_StartGameCommand].
  void startGame({String packId = 'simple_card_battle'}) {
    if (_sessionState.phase != SessionPhase.lobby) return;

    // Sync playerOrder from the current session manager.
    final playerOrder = _sessions.playerIds.toList();
    if (playerOrder.isEmpty) return;

    // Build a minimal session state that reflects connected players.
    final players = {
      for (final id in playerOrder)
        id: PlayerSessionState(
          playerId: id,
          nickname: _sessions.displayName(id) ?? id,
          isReady: _sessions.isReady(id),
          isConnected: _sessions.isConnected(id),
          reconnectToken: _sessions.getReconnectToken(id),
        ),
    };

    _sessionState = _sessionState.copyWith(
      sessionId: _gameState?.gameId ?? 'session',
      players: players,
      playerOrder: playerOrder,
    );

    // Select the rules implementation for this pack before creating the state.
    _gamePackRules = _createRulesForPack(packId);

    _sessionState = _gamePackRules.createInitialGameState(_sessionState);

    // Broadcast initial BOARD_VIEW + per-player PLAYER_VIEW.
    _broadcastViews();
  }

  // ---------------------------------------------------------------------------
  // Connection handling
  // ---------------------------------------------------------------------------

  void _handleConnection(WebSocketChannel channel) {
    final sink = _ChannelSink(channel);

    channel.stream.listen(
      (raw) => _handleMessage(raw as String, sink),
      onError: (Object e) => channel.sink.close(),
      onDone: () {
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
      case WsMessageType.setReady:
        _handleSetReady(SetReadyMessage.fromEnvelope(msg));
      case WsMessageType.ping:
        _handlePing(PingMessage.fromEnvelope(msg), sink);
      default:
        _sendError(sink, 'Unexpected message type: ${msg.type}');
    }
  }

  void _handleJoin(JoinMessage join, SessionSink sink) {
    // Attempt reconnect if the client supplies a token.
    final incomingToken = join.reconnectToken;
    String resolvedPlayerId = join.playerId;
    bool isReconnect = false;

    if (incomingToken != null && incomingToken.isNotEmpty) {
      final existingId = _sessions.findPlayerByReconnectToken(incomingToken);
      if (existingId != null) {
        resolvedPlayerId = existingId;
        isReconnect = true;
      }
    }

    final displayName = join.displayName ?? resolvedPlayerId;

    if (isReconnect) {
      // Reattach the new socket to the existing seat.
      _sessions.reconnect(playerId: resolvedPlayerId, newSink: sink);
    } else {
      _sessions.register(
        playerId: resolvedPlayerId,
        displayName: displayName,
        sink: sink,
      );
    }

    _sinkToPlayer[sink] = resolvedPlayerId;

    // Issue (or retrieve) the reconnect token for this player.
    final token = _sessions.getReconnectToken(resolvedPlayerId);

    // Acknowledge the join to the connecting player.
    sink.add(
      jsonEncode(
        JoinRoomAckMessage(
          playerId: resolvedPlayerId,
          reconnectToken: token,
          success: true,
        ).toEnvelope().toJson(),
      ),
    );

    // Notify the UI isolate.
    eventPort?.send(PlayerEvent(
      joined: true,
      playerId: resolvedPlayerId,
      displayName: displayName,
    ));

    // Send the current game state to the newly joined player (legacy).
    // Only during inGame phase to prevent the client from transitioning to
    // inGame prematurely while still in the lobby.
    if (_sessionState.phase == SessionPhase.inGame) {
      final state = _gameState;
      if (state != null) {
        sink.add(
          jsonEncode(
            StateUpdateMessage(state: state.toJson()).toEnvelope().toJson(),
          ),
        );
      }
    }

    // On reconnect during an active game, immediately re-send the player view.
    if (isReconnect && _sessionState.phase == SessionPhase.inGame) {
      final playerView =
          _gamePackRules.buildPlayerView(_sessionState, resolvedPlayerId);
      _sessions.sendToPlayer(
        resolvedPlayerId,
        PlayerViewMessage(playerView: playerView).toEnvelope().toJson(),
      );
    }

    // Broadcast updated lobby state to all players (including the new one).
    _broadcastLobbyState();
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

  void _handleSetReady(SetReadyMessage msg) {
    _sessions.setReady(msg.playerId, msg.isReady);
    _broadcastLobbyState();
  }

  // ---------------------------------------------------------------------------
  // Sprint 3: Heartbeat
  // ---------------------------------------------------------------------------

  /// Responds to a client ping with a pong carrying the same timestamp.
  void _handlePing(PingMessage ping, SessionSink sink) {
    sink.add(
      jsonEncode(PongMessage(timestamp: ping.timestamp).toEnvelope().toJson()),
    );
  }

  // ---------------------------------------------------------------------------
  // Sprint 2: hardened action pipeline
  // ---------------------------------------------------------------------------

  void _handleAction(ActionMessage action, SessionSink sink) {
    // ------------------------------------------------------------------
    // 1. Duplicate check (idempotency)
    // ------------------------------------------------------------------
    final clientId = action.clientActionId;
    if (clientId != null && clientId.isNotEmpty) {
      if (_processedActions.isAlreadyProcessed(clientId)) {
        _sendActionRejected(
          sink,
          clientActionId: clientId,
          reason: 'Duplicate action',
          code: ActionRejectedCode.duplicateAction,
        );
        return;
      }
    }

    // ------------------------------------------------------------------
    // 2. Phase check — must be inGame
    // ------------------------------------------------------------------
    if (_sessionState.phase != SessionPhase.inGame) {
      // Fall back to legacy path when session state is still in lobby or
      // the Sprint 2 pipeline has not yet been activated.
      _handleActionLegacy(action, sink);
      return;
    }

    // ------------------------------------------------------------------
    // 3. Active-player check
    // ------------------------------------------------------------------
    final turnState = _sessionState.turnState;
    if (turnState == null || turnState.activePlayerId != action.playerId) {
      _sendActionRejected(
        sink,
        clientActionId: clientId,
        reason: 'Not your turn',
        code: ActionRejectedCode.notYourTurn,
      );
      return;
    }

    // ------------------------------------------------------------------
    // 4. Allowed-action check
    // ------------------------------------------------------------------
    final allowed = _gamePackRules.getAllowedActions(
      _sessionState,
      action.playerId,
    );
    final isAllowed = allowed.any((a) => a.actionType == action.actionType);
    if (!isAllowed) {
      _sendActionRejected(
        sink,
        clientActionId: clientId,
        reason: 'Action not allowed: ${action.actionType}',
        code: ActionRejectedCode.invalidAction,
      );
      return;
    }

    // ------------------------------------------------------------------
    // 5. Record as processed (idempotency bookkeeping)
    // ------------------------------------------------------------------
    if (clientId != null && clientId.isNotEmpty) {
      _processedActions.add(clientId);
    }

    // ------------------------------------------------------------------
    // 6. Apply action (pure function → new state)
    // ------------------------------------------------------------------
    final playerAction = PlayerAction(
      playerId: action.playerId,
      type: action.actionType,
      data: action.data,
    );

    _sessionState = _gamePackRules.applyAction(
      _sessionState,
      action.playerId,
      playerAction,
    );

    // ------------------------------------------------------------------
    // 7. version++ — already handled by applyAction / addLog chain
    //    (GameSessionState.addLog increments version)
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // 8. Check game end
    // ------------------------------------------------------------------
    final endResult = _gamePackRules.checkGameEnd(_sessionState);
    if (endResult.ended) {
      final logEntry = GameLogEntry(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        eventType: 'GAME_END',
        description: 'Game over. Winners: ${endResult.winnerIds.join(', ')}',
      );
      _sessionState = _sessionState
          .copyWith(phase: SessionPhase.finished)
          .addLog(logEntry);
    }

    // ------------------------------------------------------------------
    // 9. Broadcast views
    // ------------------------------------------------------------------
    _broadcastViews();

    // ------------------------------------------------------------------
    // 10. Auto-save (Sprint 3) — fire-and-forget, never blocks the game loop
    // ------------------------------------------------------------------
    _store?.save(_sessionState).catchError((_) {});
  }

  /// Legacy action handler used when the session is still using [GamePackInterface]
  /// (lobby phase or before [startGame] is called).
  void _handleActionLegacy(ActionMessage action, SessionSink sink) {
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

    bool valid;
    try {
      valid = gamePack.validateAction(playerAction, state);
    } catch (e) {
      _sendError(sink, 'Action validation error: $e');
      return;
    }

    if (!valid) {
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

  // ---------------------------------------------------------------------------
  // View broadcasting
  // ---------------------------------------------------------------------------

  /// Sends [BoardView] to all clients and [PlayerView] individually to each player.
  ///
  /// Also forwards the [BoardView] to the UI isolate via [eventPort] so the
  /// [GameBoardPlayScreen] can update without subscribing to the WebSocket.
  void _broadcastViews() {
    final boardView = _gamePackRules.buildBoardView(_sessionState);
    final boardViewEnvelope =
        BoardViewMessage(boardView: boardView).toEnvelope().toJson();

    _sessions.broadcastBoardView(boardViewEnvelope);

    // Notify the UI isolate.
    eventPort?.send(BoardViewEvent(boardView: boardView.toJson()));

    for (final playerId in _sessions.playerIds) {
      final playerView =
          _gamePackRules.buildPlayerView(_sessionState, playerId);
      _sessions.sendToPlayer(
        playerId,
        PlayerViewMessage(playerView: playerView).toEnvelope().toJson(),
      );
    }
  }

  /// Broadcasts the current lobby state to all connected players and notifies
  /// the UI isolate so it can update the [LobbyScreen] without parsing JSON.
  void _broadcastLobbyState() {
    final lobby = _sessions.buildLobbyState();
    _sessions.broadcast(jsonEncode(lobby.toEnvelope().toJson()));

    // Notify the UI isolate.
    eventPort?.send(LobbyStateEvent(
      players: lobby.players.map((p) => p.toJson()).toList(),
      canStart: lobby.canStart,
    ));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

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

  void _sendActionRejected(
    SessionSink sink, {
    String? clientActionId,
    required String reason,
    required ActionRejectedCode code,
  }) {
    sink.add(
      jsonEncode(
        ActionRejectedMessage(
          clientActionId: clientActionId,
          reason: reason,
          code: code,
        ).toEnvelope().toJson(),
      ),
    );
  }

  /// Sprint 3: ungraceful disconnect — mark the player as offline rather than
  /// removing them so they can reclaim their seat via reconnect token.
  void _cleanUpOrphan(SessionSink sink) {
    final playerId = _sinkToPlayer.remove(sink);
    if (playerId == null) return;

    if (_sessions.isConnected(playerId)) {
      final displayName = _sessions.displayName(playerId) ?? playerId;

      // Mark offline; do NOT unregister (preserves seat + token).
      _sessions.markDisconnected(playerId);

      // Persist the current state so it survives server restarts.
      if (_sessionState.phase == SessionPhase.inGame) {
        _store?.save(_sessionState).catchError((_) {});
      }

      // Notify the UI isolate.
      eventPort?.send(PlayerEvent(
        joined: false,
        playerId: playerId,
        displayName: displayName,
      ));

      // Broadcast updated lobby state so other clients show the offline badge.
      _broadcastLobbyState();
    }
  }
}
