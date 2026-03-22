import 'dart:async';
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
import '../shared/game_pack/packs/stockpile_rules.dart';
import '../shared/game_pack/player_action.dart';
import '../shared/game_session/game_session_state.dart';
import '../shared/game_session/game_log_entry.dart';
import '../shared/game_session/player_session_state.dart';
import '../shared/game_session/session_phase.dart';
import '../shared/messages/action_message.dart';
import '../shared/messages/node_message.dart';
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
import 'server_isolate.dart'
    show
        BoardViewEvent,
        ForceEndVoteResultEvent,
        ForceEndVoteStartedEvent,
        GameResetEvent,
        LobbyStateEvent,
        PlayerEvent;
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

  // ---------------------------------------------------------------------------
  // Zombie-connection detection (server-side heartbeat)
  // ---------------------------------------------------------------------------

  /// Tracks the last time a message was received from each sink.
  final Map<SessionSink, DateTime> _lastSeen = {};

  /// Periodic timer that closes stale connections where [_lastSeen] exceeds
  /// [_kZombieThreshold].
  Timer? _heartbeatTimer;

  static const _kZombieThreshold = Duration(seconds: 45);
  static const _kHeartbeatCheckInterval = Duration(seconds: 20);

  // ---------------------------------------------------------------------------
  // Offline-player turn auto-skip
  // ---------------------------------------------------------------------------

  static const _kDisconnectedTurnTimeout = Duration(seconds: 60);
  Timer? _disconnectedTurnTimer;

  /// Override for the offline-turn auto-skip timeout.
  ///
  /// Provided for testing only — production code uses [_kDisconnectedTurnTimeout].
  final Duration? _disconnectedTurnTimeoutOverride;

  // ---------------------------------------------------------------------------
  // Force-end vote state
  // ---------------------------------------------------------------------------

  bool _voteActive = false;

  /// Tracks each connected player's vote: true = agree, false = disagree.
  final Map<String, bool> _votes = {};

  /// Auto-resolve timer; fires after 30 seconds if not all players have voted.
  Timer? _voteTimer;

  /// Override for the force-end vote timeout (seconds).
  ///
  /// Provided for testing only — production code uses [_kForceEndVoteTimeout].
  final Duration? _voteTimeoutOverride;

  static const _kForceEndVoteTimeout = Duration(seconds: 30);

  GameServer({
    required this.gamePack,
    this.eventPort,
    GameStateStore? store,
    Duration? disconnectedTurnTimeoutOverride,
    Duration? voteTimeoutOverride,
  })  : _store = store,
        _disconnectedTurnTimeoutOverride = disconnectedTurnTimeoutOverride,
        _voteTimeoutOverride = voteTimeoutOverride;

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

    // Start the server-side zombie-connection detection timer.
    _heartbeatTimer = Timer.periodic(
      _kHeartbeatCheckInterval,
      (_) => _checkZombieConnections(),
    );
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _disconnectedTurnTimer?.cancel();
    _disconnectedTurnTimer = null;
    _voteTimer?.cancel();
    _voteTimer = null;
    _voteActive = false;
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
      case 'stockpile':
        return StockpileRules();
      case 'simple_card_battle':
      case 'simple_card_game':
      default:
        return const SimpleCardGameRules();
    }
  }

  /// Resets the session back to the lobby phase.
  ///
  /// Clears all game state, resets every player's ready flag, broadcasts a
  /// [WsMessageType.gameReset] to all connected clients so they can transition
  /// back to the lobby screen, then broadcasts the refreshed lobby state.
  ///
  /// Called by the server isolate when it receives a [_ResetGameCommand].
  void resetGame() {
    if (_sessionState.phase == SessionPhase.lobby) return;

    // If a vote was active, cancel it cleanly before resetting.
    if (_voteActive) {
      _voteTimer?.cancel();
      _voteTimer = null;
      _voteActive = false;
      _votes.clear();
    }

    // Reset each player's ready state so the lobby starts fresh.
    for (final playerId in _sessions.playerIds) {
      _sessions.setReady(playerId, false);
    }

    // Wipe game-specific session state back to an empty lobby.
    _sessionState = GameSessionState(
      sessionId: 'default',
      phase: SessionPhase.lobby,
      players: const {},
      playerOrder: const [],
      version: 0,
      log: const [],
    );

    // Tell every connected GameNode to return to the lobby screen.
    _sessions.broadcast(
      jsonEncode(
        WsMessage(type: WsMessageType.gameReset, payload: {}).toJson(),
      ),
    );

    // Notify the UI isolate — normal (non-vote-triggered) reset.
    eventPort?.send(const GameResetEvent(forcedByVote: false));

    // Send a fresh lobby snapshot so GameNode lobby screens update immediately.
    _broadcastLobbyState();
  }

  /// Transitions the session from lobby to in-game.
  ///
  /// The optional [packId] selects which game-pack rules to use.
  /// Defaults to [SimpleCardGameRules] when omitted.
  ///
  /// Called by the server isolate when it receives a [_StartGameCommand].
  void startGame({String packId = 'simple_card_battle'}) {
    if (_sessionState.phase != SessionPhase.lobby) return;

    // Select the rules first so we can validate player count.
    final rules = _createRulesForPack(packId);
    final connectedCount =
        _sessions.playerIds.where((id) => _sessions.isConnected(id)).length;

    if (connectedCount < rules.minPlayers) {
      // Not enough players — broadcast error and abort.
      _sessions.broadcast(jsonEncode(WsMessage(
        type: WsMessageType.error,
        payload: {
          'reason':
              '인원 부족: 최소 ${rules.minPlayers}명이 필요합니다 (현재 $connectedCount명)',
        },
      ).toJson()));
      return;
    }
    if (connectedCount > rules.maxPlayers) {
      _sessions.broadcast(jsonEncode(WsMessage(
        type: WsMessageType.error,
        payload: {
          'reason':
              '인원 초과: 최대 ${rules.maxPlayers}명까지 가능합니다 (현재 $connectedCount명)',
        },
      ).toJson()));
      return;
    }

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

    // Use the rules instance created above for validation.
    _gamePackRules = rules;

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
    // Update last-seen timestamp for zombie detection.
    _lastSeen[sink] = DateTime.now();

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
      case WsMessageType.nodeMessage:
        _handleNodeMessage(NodeMessage.fromEnvelope(msg));
      case WsMessageType.forceEndVote:
        _handleForceEndVote(msg);
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

    // On join during an active game, send the full current view.
    // This covers both reconnects (token matched) and fresh joins where the
    // token was lost (server restart, token mismatch). In both cases the client
    // needs PlayerViewMessage to show the correct game-pack UI; the legacy
    // StateUpdateMessage alone only triggers the fallback UI.
    if (_sessionState.phase == SessionPhase.inGame) {
      if (isReconnect) {
        // Cancel any pending auto-skip timer for the returning active player.
        final turnState = _sessionState.turnState;
        if (turnState?.activePlayerId == resolvedPlayerId) {
          _disconnectedTurnTimer?.cancel();
          _disconnectedTurnTimer = null;
        }
      }

      final playerView =
          _gamePackRules.buildPlayerView(_sessionState, resolvedPlayerId);
      _sessions.sendToPlayer(
        resolvedPlayerId,
        PlayerViewMessage(playerView: playerView).toEnvelope().toJson(),
      );

      // Also send the board view so the client is fully in sync.
      final boardView = _gamePackRules.buildBoardView(_sessionState);
      sink.add(jsonEncode(
        BoardViewMessage(boardView: boardView).toEnvelope().toJson(),
      ));

      // Notify all other players that this player is back online.
      _sessions.broadcast(
        jsonEncode(
          WsMessage(
            type: WsMessageType.playerReconnected,
            payload: {
              'playerId': resolvedPlayerId,
              'nickname': displayName,
            },
          ).toJson(),
        ),
        excludePlayerId: resolvedPlayerId,
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

    // Notify the UI isolate — deliberate LEAVE, not a temporary disconnect.
    eventPort?.send(PlayerEvent(
      joined: false,
      playerId: leave.playerId,
      displayName: displayName,
      isTemporaryDisconnect: false,
    ));

    _sessions.broadcast(
      jsonEncode(
        WsMessage(
          type: WsMessageType.leave,
          payload: {'playerId': leave.playerId},
        ).toJson(),
      ),
    );

    // Refresh lobby state so the GameBoard reflects the updated player list.
    _broadcastLobbyState();
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
  // Node-to-node message routing
  // ---------------------------------------------------------------------------

  /// Routes a [NodeMessage] from one GameNode to another (or broadcasts it).
  ///
  /// Processing steps:
  ///   1. Sender must be a registered player — prevents spoofed messages.
  ///   2. The active [GamePackRules.onNodeMessage] hook may block or transform
  ///      the message.  Returning `null` silently drops the message.
  ///   3. Routing: unicast to [NodeMessage.toPlayerId] when specified,
  ///      broadcast to all connected players otherwise.
  void _handleNodeMessage(NodeMessage msg) {
    // 1. Sender validation.
    if (!_sessions.playerIds.contains(msg.fromPlayerId)) return;

    // 2. GamePack hook — null return blocks delivery.
    final routed = _gamePackRules.onNodeMessage(msg, _sessionState);
    if (routed == null) return;

    // 3. Routing.
    final envelope = jsonEncode(routed.toEnvelope().toJson());
    if (routed.toPlayerId == null) {
      _sessions.broadcast(envelope);
    } else {
      _sessions.send(routed.toPlayerId!, envelope);
    }
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
    _broadcastActionNotification(action.playerId);

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
    // Build views from the pack, then inject platform-managed orientation keys.
    final rawBoardView = _gamePackRules.buildBoardView(_sessionState);
    final boardView = rawBoardView.copyWith(data: {
      '_boardOrientation': _gamePackRules.boardOrientation,
      '_nodeOrientation': _gamePackRules.nodeOrientation,
      ...rawBoardView.data,
    });

    final boardViewEnvelope =
        BoardViewMessage(boardView: boardView).toEnvelope().toJson();

    _sessions.broadcastBoardView(boardViewEnvelope);

    // Notify the UI isolate.
    eventPort?.send(BoardViewEvent(boardView: boardView.toJson()));

    for (final playerId in _sessions.playerIds) {
      final rawPlayerView =
          _gamePackRules.buildPlayerView(_sessionState, playerId);
      final playerView = rawPlayerView.copyWith(data: {
        '_nodeOrientation': _gamePackRules.nodeOrientation,
        ...rawPlayerView.data,
      });
      _sessions.sendToPlayer(
        playerId,
        PlayerViewMessage(playerView: playerView).toEnvelope().toJson(),
      );
    }

    // After every state broadcast, check if the active player is offline and
    // start (or maintain) the auto-skip timer.
    _checkDisconnectedTurn();
  }

  /// Sends an [WsMessageType.actionNotification] to every connected player
  /// except the actor, containing the latest log entry description.
  ///
  /// Called immediately after [_broadcastViews] so GameNode players can show
  /// a toast notification for actions taken by other players.
  void _broadcastActionNotification(String actorId) {
    final log = _sessionState.log;
    if (log.isEmpty) return;
    final latest = log.last;
    final notification = WsMessage(
      type: WsMessageType.actionNotification,
      payload: {
        'description': latest.description,
        'actorId': actorId,
      },
    );
    _sessions.broadcast(
      jsonEncode(notification.toJson()),
      excludePlayerId: actorId,
    );
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
  ///
  /// No auto-eviction timer is started; the seat is preserved until game end.
  void _cleanUpOrphan(SessionSink sink) {
    _lastSeen.remove(sink);
    final playerId = _sinkToPlayer.remove(sink);
    if (playerId == null) return;

    if (_sessions.isConnected(playerId)) {
      final displayName = _sessions.displayName(playerId) ?? playerId;

      if (_sessionState.phase == SessionPhase.lobby) {
        // Lobby: no game in progress — fully remove the player so the slot is
        // freed immediately and the lobby list stays clean.
        _sessions.unregister(playerId);

        // Notify the UI isolate — permanent removal.
        eventPort?.send(PlayerEvent(
          joined: false,
          playerId: playerId,
          displayName: displayName,
          isTemporaryDisconnect: false,
        ));

        // Broadcast LEAVE so other clients remove the player from their lobby UI.
        _sessions.broadcast(
          jsonEncode(
            WsMessage(
              type: WsMessageType.leave,
              payload: {'playerId': playerId},
            ).toJson(),
          ),
        );
      } else {
        // In-game: preserve the seat so the player can reconnect via token.
        _sessions.markDisconnected(playerId);

        // Persist the current state so it survives server restarts.
        _store?.save(_sessionState).catchError((_) {});

        // Notify the UI isolate — temporary disconnect, seat preserved.
        eventPort?.send(PlayerEvent(
          joined: false,
          playerId: playerId,
          displayName: displayName,
          isTemporaryDisconnect: true,
        ));

        // Tell all clients about the disconnect.
        _broadcastPlayerDisconnected(playerId, displayName);

        // If this player was the active player, start the auto-skip timer.
        _checkDisconnectedTurn();
      }

      // Always refresh the lobby state for all remaining clients.
      _broadcastLobbyState();
    }
  }

  // ---------------------------------------------------------------------------
  // Zombie-connection detection
  // ---------------------------------------------------------------------------

  void _checkZombieConnections() {
    final now = DateTime.now();
    final stale = _lastSeen.entries
        .where((e) => now.difference(e.value) > _kZombieThreshold)
        .map((e) => e.key)
        .toList();
    for (final sink in stale) {
      // Closing the sink triggers onDone → _cleanUpOrphan.
      sink.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Offline-player turn auto-skip
  // ---------------------------------------------------------------------------

  void _checkDisconnectedTurn() {
    if (_sessionState.phase != SessionPhase.inGame) return;
    final activeId = _sessionState.turnState?.activePlayerId;
    if (activeId == null) return;

    if (_sessions.isConnected(activeId)) {
      // Active player is online — cancel any pending timer.
      _disconnectedTurnTimer?.cancel();
      _disconnectedTurnTimer = null;
      return;
    }

    // Active player is offline and no timer is running yet — start one.
    if (_disconnectedTurnTimer == null) {
      _broadcastTurnAutoSkipWarning(activeId);
      final timeout =
          _disconnectedTurnTimeoutOverride ?? _kDisconnectedTurnTimeout;
      _disconnectedTurnTimer = Timer(timeout, () {
        _autoSkipDisconnectedTurn(activeId);
      });
    }
  }

  void _autoSkipDisconnectedTurn(String playerId) {
    _disconnectedTurnTimer = null;

    // Guard: phase may have changed while the timer was pending.
    if (_sessionState.phase != SessionPhase.inGame) return;
    if (_sessionState.turnState?.activePlayerId != playerId) return;
    if (_sessions.isConnected(playerId)) return;

    final autoAction = PlayerAction(
      playerId: playerId,
      type: 'END_TURN',
      data: const {'auto': true, 'reason': 'disconnected'},
    );
    _sessionState = _gamePackRules.applyAction(_sessionState, playerId, autoAction);
    _sessionState = _sessionState.addLog(GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'AUTO_SKIP',
      description:
          '${_sessions.displayName(playerId) ?? playerId} 자동 스킵 (오프라인)',
    ));

    // _broadcastViews() calls _checkDisconnectedTurn() again, which handles
    // the case where the next active player is also offline.
    _broadcastViews();
  }

  // ---------------------------------------------------------------------------
  // New broadcast helpers
  // ---------------------------------------------------------------------------

  void _broadcastPlayerDisconnected(String playerId, String nickname) {
    _sessions.broadcast(jsonEncode(WsMessage(
      type: WsMessageType.playerDisconnected,
      payload: {
        'playerId': playerId,
        'nickname': nickname,
      },
    ).toJson()));
  }

  void _broadcastTurnAutoSkipWarning(String playerId) {
    _sessions.broadcast(jsonEncode(WsMessage(
      type: WsMessageType.turnAutoSkipWarning,
      payload: {
        'playerId': playerId,
        'nickname': _sessions.displayName(playerId) ?? playerId,
        'skipInSeconds': _kDisconnectedTurnTimeout.inSeconds,
      },
    ).toJson()));
  }

  // ---------------------------------------------------------------------------
  // Force-end vote
  // ---------------------------------------------------------------------------

  /// Initiates a force-end vote among all currently connected players.
  ///
  /// Broadcasts [WsMessageType.forceEndVoteStart] to all connected GameNodes
  /// and starts a 30-second auto-resolve timer.
  ///
  /// Does nothing if:
  ///   - the session is not in the inGame phase, or
  ///   - a vote is already in progress.
  void startForceEndVote() {
    if (_sessionState.phase != SessionPhase.inGame) return;
    if (_voteActive) return;

    _voteActive = true;
    _votes.clear();

    final connectedCount = _sessions.playerIds
        .where((id) => _sessions.isConnected(id))
        .length;

    _sessions.broadcast(jsonEncode(WsMessage(
      type: WsMessageType.forceEndVoteStart,
      payload: {'playerCount': connectedCount, 'timeoutSeconds': 30},
    ).toJson()));

    // Notify the UI isolate so the GameBoard can update its state.
    eventPort?.send(ForceEndVoteStartedEvent(playerCount: connectedCount));

    // Auto-resolve after the configured timeout.
    final timeout = _voteTimeoutOverride ?? _kForceEndVoteTimeout;
    _voteTimer = Timer(timeout, _resolveVote);
  }

  void _handleForceEndVote(WsMessage msg) {
    if (!_voteActive) return;

    final playerId = msg.payload['playerId'] as String?;
    final agree = msg.payload['agree'] as bool? ?? false;

    if (playerId == null || !_sessions.playerIds.contains(playerId)) return;

    _votes[playerId] = agree;

    // Resolve immediately once all currently-connected players have voted.
    final connectedPlayers = _sessions.playerIds
        .where((id) => _sessions.isConnected(id))
        .toList();
    final votedConnected =
        _votes.keys.where((id) => connectedPlayers.contains(id)).length;
    if (votedConnected >= connectedPlayers.length) {
      _resolveVote();
    }
  }

  void _resolveVote() {
    if (!_voteActive) return;
    _voteActive = false;
    _voteTimer?.cancel();
    _voteTimer = null;

    final connectedPlayers = _sessions.playerIds
        .where((id) => _sessions.isConnected(id))
        .toList();
    final total = connectedPlayers.length;
    final agreeCount = _votes.values.where((v) => v).length;
    final majority = agreeCount > total / 2;

    _sessions.broadcast(jsonEncode(WsMessage(
      type: WsMessageType.forceEndVoteResult,
      payload: {
        'agreed': majority,
        'agreeCount': agreeCount,
        'totalCount': total,
      },
    ).toJson()));

    // Notify the UI isolate so it can reset the vote button regardless of outcome.
    eventPort?.send(ForceEndVoteResultEvent(
      agreed: majority,
      agreeCount: agreeCount,
      totalCount: total,
    ));

    if (majority) {
      _resetGameForcedByVote();
    }
  }

  /// Resets the game to the lobby as a consequence of a passed force-end vote.
  ///
  /// Behaves like [resetGame] but sends [GameResetEvent] with [forcedByVote] = true.
  void _resetGameForcedByVote() {
    // Reset player ready states.
    for (final playerId in _sessions.playerIds) {
      _sessions.setReady(playerId, false);
    }

    // Wipe game-specific session state back to an empty lobby.
    _sessionState = GameSessionState(
      sessionId: 'default',
      phase: SessionPhase.lobby,
      players: const {},
      playerOrder: const [],
      version: 0,
      log: const [],
    );

    // Tell every connected GameNode to return to the lobby screen.
    _sessions.broadcast(
      jsonEncode(
        WsMessage(type: WsMessageType.gameReset, payload: {}).toJson(),
      ),
    );

    // Notify the UI isolate — this reset was triggered by a passing vote.
    eventPort?.send(const GameResetEvent(forcedByVote: true));

    // Send a fresh lobby snapshot.
    _broadcastLobbyState();
  }

  // ---------------------------------------------------------------------------
  // Test-only helpers
  //
  // These methods are package-private (no leading underscore) so that unit
  // tests can drive the server without a real WebSocket connection.  They must
  // NOT be called from production code.
  // ---------------------------------------------------------------------------

  /// Registers a player directly into the session manager.
  ///
  /// Allows tests to set up a connected player without going through the full
  /// WebSocket JOIN handshake.
  void injectSessionForTest(
    String playerId,
    String displayName,
    SessionSink sink,
  ) {
    _sessions.register(
      playerId: playerId,
      displayName: displayName,
      sink: sink,
    );
    _sinkToPlayer[sink] = playerId;
  }

  /// Feeds a raw JSON string into [_handleMessage] as if it arrived from [sink].
  ///
  /// Allows tests to send arbitrary messages without a real WebSocket.
  void handleMessageForTest(String raw, SessionSink sink) {
    _handleMessage(raw, sink);
  }
}
