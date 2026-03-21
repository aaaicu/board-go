import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../shared/ws_client.dart';
import '../shared/player_identity.dart';
import '../../shared/game_pack/views/allowed_action.dart';
import '../../shared/game_pack/views/player_view.dart';
import '../../shared/game_session/session_phase.dart';
import '../../shared/messages/action_message.dart';
import '../../shared/messages/join_message.dart';
import '../../shared/messages/join_room_ack_message.dart';
import '../../shared/messages/lobby_state_message.dart';
import '../../shared/messages/player_view_message.dart';
import '../../shared/messages/set_ready_message.dart';
import '../../shared/messages/state_update_message.dart';
import '../../shared/messages/node_message.dart';
import '../../shared/messages/ws_message.dart';
import '../../shared/game_pack/packs/simple_card_game_emotes.dart';
import 'allowed_actions_widget.dart';
import 'discovery_screen.dart';
import 'game_over_widget.dart';
import 'hand_widget.dart';
import 'lobby_waiting_screen.dart';
import 'player_action_widget.dart';

/// Possible UI phases for the GameNode.
enum _NodePhase { discovery, lobby, inGame }

/// The main screen displayed on a player's phone.
///
/// Phase transitions:
///   [discovery] → Connect to server → JOIN_ROOM_ACK(success) → [lobby]
///   [lobby]    → Host starts game  → (Sprint 2) → [inGame]
///
/// Sprint 3 additions:
///   - Connection-state overlay: shows a reconnecting banner when the
///     WebSocket drops and auto-reconnect is in progress.
///   - Auto-reconnect: [WsClient] retries with exponential backoff and
///     re-sends JOIN with the saved reconnect token once re-connected.
class GameNodeScreen extends StatefulWidget {
  const GameNodeScreen({super.key});

  @override
  State<GameNodeScreen> createState() => _GameNodeScreenState();
}

class _GameNodeScreenState extends State<GameNodeScreen> {
  WsClient? _client;
  StreamSubscription<WsConnectionState>? _connStateSub;
  _NodePhase _phase = _NodePhase.discovery;
  bool _disposing = false;

  /// The WebSocket URL of the currently connected server.
  /// Stored so auto-reconnect can re-use the same URL.
  String? _wsUrl;

  /// Set after a successful JOIN_ROOM_ACK.
  String? _assignedPlayerId;
  String? _reconnectToken;

  /// Latest lobby state received from the server.
  LobbyStateMessage _lobbyState = const LobbyStateMessage(
    players: [],
    canStart: false,
  );

  /// Whether this player has signalled ready in the lobby.
  bool _isReady = false;

  /// Latest game state (used in inGame phase — legacy path).
  Map<String, dynamic>? _gameState;

  /// Latest [PlayerView] received from the server (Sprint 2).
  PlayerView? _playerView;

  /// Loaded asynchronously in [initState]; null while loading.
  PlayerIdentity? _identity;

  /// Server URL from the last session, loaded on startup.
  /// Non-null = show "이어하기" button on the discovery screen.
  String? _savedServerUrl;

  // ---------------------------------------------------------------------------
  // Sprint 3: connection state
  // ---------------------------------------------------------------------------

  WsConnectionState _connState = WsConnectionState.connected;
  int _reconnectAttempts = 0;

  // ---------------------------------------------------------------------------
  // Disconnect handling state
  // ---------------------------------------------------------------------------

  /// Non-null when a TURN_AUTO_SKIP_WARNING has been received and the warning
  /// banner should be displayed to all players.
  Map<String, dynamic>? _autoSkipWarning;

  // ---------------------------------------------------------------------------
  // Node-to-node messaging state
  // ---------------------------------------------------------------------------

  /// Ring-buffer of the most recently received [NodeMessage]s (newest first).
  ///
  /// Capped at 10 entries to bound memory usage.  The UI uses this list to
  /// render transient emote overlays.
  final List<NodeMessage> _receivedNodeMessages = [];

  /// Currently visible emote overlays.  Each entry is auto-removed after 2 s.
  final List<({String emoji, String fromNickname})> _emoteOverlays = [];

  /// Currently visible chat overlays.  Each entry is auto-removed after 3 s.
  final List<({String text, String fromNickname})> _chatOverlays = [];

  // ---------------------------------------------------------------------------
  // Action pending guard
  //
  // Set to true when an action is sent and reset when the next PlayerView
  // arrives from the server.  This prevents duplicate submissions when the
  // player taps a button (e.g. End Turn) rapidly before the acknowledgement
  // comes back — which in a single-player game caused the round counter to
  // advance multiple times, eventually ending the game prematurely and
  // showing the "상대방 턴" spinner indefinitely.
  // ---------------------------------------------------------------------------

  bool _actionPending = false;

  @override
  void initState() {
    super.initState();
    PlayerIdentity.load().then((identity) {
      if (mounted) setState(() => _identity = identity);
    });
    PlayerIdentity.loadLastServerUrl().then((url) {
      if (mounted) setState(() => _savedServerUrl = url);
    });
  }

  @override
  void dispose() {
    _disposing = true;
    _connStateSub?.cancel();
    _client?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Nickname editing
  // ---------------------------------------------------------------------------

  Future<void> _showNicknameDialog() async {
    final controller = TextEditingController(
      text: _identity?.nickname ?? 'Player',
    );

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Nickname'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter your nickname'),
          autofocus: true,
          maxLength: 24,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newNickname = controller.text.trim();
              if (newNickname.isNotEmpty) {
                await PlayerIdentity.saveNickname(newNickname);
                if (mounted) {
                  setState(() {
                    _identity = PlayerIdentity(
                      deviceId: _identity!.deviceId,
                      nickname: newNickname,
                    );
                  });
                }
              }
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  Future<void> _connectTo(String wsUrl) async {
    final identity = _identity;
    if (identity == null) return;

    // Persist URL for reconnect reference.
    _wsUrl = wsUrl;

    // Load a previously saved reconnect token for this server (survives app restart).
    _reconnectToken ??= await PlayerIdentity.loadReconnectToken(wsUrl);

    // Dispose of any prior client before creating a new one.
    await _connStateSub?.cancel();
    await _client?.dispose();

    final client = WsClient(
      uri: Uri.parse(wsUrl),
      reconnectToken: _reconnectToken,
      onConnectionStateChange: (connected) {
        if (mounted && !_disposing && !connected && _phase != _NodePhase.discovery) {
          // Do not jump back to discovery — let auto-reconnect handle it.
        }
      },
    );

    // Subscribe to connection state changes BEFORE connecting.
    _connStateSub = client.connectionState.listen(_onConnectionStateChange);

    try {
      await client.connect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
      return;
    }

    // Listen for all incoming messages.
    client.messages.listen((raw) {
      if (raw == wsClientReconnectHint) {
        // Auto-reconnect succeeded — re-send JOIN with the saved token.
        _sendJoin(client, identity);
        return;
      }
      try {
        final msg = WsMessage.fromJson(
          jsonDecode(raw as String) as Map<String, dynamic>,
        );
        _handleServerMessage(msg);
      } catch (_) {
        // Ignore malformed messages.
      }
    });

    setState(() => _client = client);

    // Send initial JOIN.
    _sendJoin(client, identity);
  }

  void _sendJoin(WsClient client, PlayerIdentity identity) {
    client.sendMessage(
      JoinMessage.join(
        playerId: identity.deviceId,
        displayName: identity.nickname,
        reconnectToken: _reconnectToken,
      ).toEnvelope(),
    );
  }

  // ---------------------------------------------------------------------------
  // Sprint 3: connection state handling
  // ---------------------------------------------------------------------------

  void _onConnectionStateChange(WsConnectionState state) {
    if (!mounted || _disposing) return;
    setState(() {
      _connState = state;
      if (state == WsConnectionState.reconnecting) {
        _reconnectAttempts++;
      } else if (state == WsConnectionState.connected && _reconnectAttempts > 0) {
        // Reconnect succeeded — show a snack bar and reset counter.
        _reconnectAttempts = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('재접속됨')),
            );
          }
        });
      }
    });
  }

  void _handleServerMessage(WsMessage msg) {
    if (!mounted || _disposing) return;

    switch (msg.type) {
      case WsMessageType.joinRoomAck:
        _handleJoinRoomAck(JoinRoomAckMessage.fromEnvelope(msg));

      case WsMessageType.lobbyState:
        setState(() {
          _lobbyState = LobbyStateMessage.fromEnvelope(msg);
          // Sync local ready state with the server's authoritative state.
          // This handles reconnect scenarios where the server preserved the
          // ready flag but the client's local state was reset to false.
          final myId = _assignedPlayerId ?? _identity?.deviceId;
          if (myId != null) {
            final myInfo = _lobbyState.players
                .where((p) => p.playerId == myId)
                .firstOrNull;
            if (myInfo != null) _isReady = myInfo.isReady;
          }
        });

      case WsMessageType.stateUpdate:
        final update = StateUpdateMessage.fromEnvelope(msg);
        setState(() {
          _gameState = update.state;
          // If we receive a game state update we've transitioned to inGame.
          if (_phase == _NodePhase.lobby) _phase = _NodePhase.inGame;
        });

      case WsMessageType.playerView:
        final pvm = PlayerViewMessage.fromEnvelope(msg);
        setState(() {
          _playerView = pvm.playerView;
          if (_phase == _NodePhase.lobby) _phase = _NodePhase.inGame;
          // Server has processed our action and replied — unblock the UI.
          _actionPending = false;
          // A new PLAYER_VIEW means a new turn has started; clear the warning.
          _autoSkipWarning = null;
        });

      // BOARD_VIEW is for the GameBoard (iPad); GameNode ignores it.
      case WsMessageType.boardView:
        break;

      case WsMessageType.gameReset:
        // Game ended — the old token is no longer useful for this session.
        PlayerIdentity.clearReconnectToken();
        setState(() {
          _phase = _NodePhase.lobby;
          _playerView = null;
          _gameState = null;
          _isReady = false;
          _actionPending = false;
          _autoSkipWarning = null;
          _savedServerUrl = null;
        });

      case WsMessageType.playerDisconnected:
        final nickname =
            msg.payload['nickname'] as String? ?? msg.payload['playerId'] as String? ?? '???';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$nickname 연결 끊김')),
            );
          }
        });

      case WsMessageType.turnAutoSkipWarning:
        setState(() => _autoSkipWarning = Map<String, dynamic>.from(msg.payload));

      case WsMessageType.nodeMessage:
        _handleNodeMessage(NodeMessage.fromEnvelope(msg));

      default:
        break;
    }
  }

  /// Appends [msg] to the ring-buffer and delegates to [_onNodeMessageReceived].
  void _handleNodeMessage(NodeMessage msg) {
    if (!mounted || _disposing) return;
    setState(() {
      _receivedNodeMessages.insert(0, msg);
      if (_receivedNodeMessages.length > 10) _receivedNodeMessages.removeLast();
    });
    _onNodeMessageReceived(msg);
  }

  /// Extension point for game-specific node message handling.
  ///
  /// Currently implements emote overlay display for [SimpleCardGameEmote.emote]
  /// messages.  Future game packs can extend this method to add custom reactions.
  void _onNodeMessageReceived(NodeMessage msg) {
    // Resolve fromPlayerId → nickname via the latest lobby snapshot.
    final fromInfo = _lobbyState.players
        .where((p) => p.playerId == msg.fromPlayerId)
        .firstOrNull;
    final nickname = fromInfo?.nickname ?? msg.fromPlayerId;

    if (msg.type == SimpleCardGameEmote.emote) {
      final emoji = msg.payload['emoji'] as String?;
      if (emoji == null) return;
      setState(() => _emoteOverlays.add((emoji: emoji, fromNickname: nickname)));
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _emoteOverlays.removeAt(0));
      });
    } else if (msg.type == SimpleCardGameEmote.chat) {
      final text = msg.payload['text'] as String?;
      if (text == null || text.isEmpty) return;
      setState(() => _chatOverlays.add((text: text, fromNickname: nickname)));
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _chatOverlays.removeAt(0));
      });
    }
  }

  void _handleJoinRoomAck(JoinRoomAckMessage ack) {
    if (ack.success) {
      setState(() {
        _assignedPlayerId = ack.playerId;
        _reconnectToken = ack.reconnectToken;
        // Propagate the token to the client so auto-reconnect re-uses it.
        _client?.reconnectToken = ack.reconnectToken;
        _phase = _NodePhase.lobby;
        _isReady = false;
      });
      // Persist the token so it survives app restarts.
      final wsUrl = _wsUrl;
      final token = ack.reconnectToken;
      if (wsUrl != null && token != null) {
        PlayerIdentity.saveReconnectToken(wsUrl, token);
      }
    } else {
      final errorCode = ack.errorCode ?? 'UNKNOWN';
      final errorMessage = ack.errorMessage ?? '접속에 실패했습니다.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[$errorCode] $errorMessage')),
      );
      _client?.disconnect();
      setState(() {
        _client = null;
        _phase = _NodePhase.discovery;
      });
    }
  }

  void _sendReadyToggle(bool newReady) {
    final playerId = _assignedPlayerId ?? _identity?.deviceId;
    if (playerId == null) return;

    try {
      _client?.sendMessage(
        SetReadyMessage(playerId: playerId, isReady: newReady).toEnvelope(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('준비 상태 전송 실패: $e')),
        );
      }
    }
    setState(() => _isReady = newReady);
  }

  void _sendAction(String actionType, [Map<String, dynamic> data = const {}]) {
    // Guard: if a previous action is still awaiting a server response, drop
    // the duplicate.  This prevents rapid tapping (e.g. END_TURN spam) from
    // sending multiple identical actions before the server has acknowledged
    // the first one.
    if (_actionPending) return;

    final identity = _identity;
    if (identity == null) return;

    setState(() => _actionPending = true);

    _client?.sendMessage(
      ActionMessage(
        playerId: _assignedPlayerId ?? identity.deviceId,
        actionType: actionType,
        data: data,
      ).toEnvelope(),
    );
  }

  /// Sends a [NodeMessage] to a specific player or broadcasts it to all.
  ///
  /// [toPlayerId] `null` = broadcast; non-null = unicast.
  void _sendNodeMessage(
    String type, {
    String? toPlayerId,
    Map<String, dynamic> payload = const {},
  }) {
    final identity = _identity;
    if (identity == null) return;
    _client?.sendMessage(
      NodeMessage(
        fromPlayerId: _assignedPlayerId ?? identity.deviceId,
        toPlayerId: toPlayerId,
        type: type,
        payload: payload,
      ).toEnvelope(),
    );
  }

  /// 게임 종료 후 연결은 유지한 채 대기실(lobby)로 돌아간다.
  /// GameBoard가 resetGame()을 호출하면 GAME_RESET 브로드캐스트가 오고
  /// 이미 lobby 상태이므로 자연스럽게 상태가 갱신된다.
  void _returnToLobby() {
    final playerId = _assignedPlayerId ?? _identity?.deviceId;
    if (playerId != null) {
      // 서버에 ready=false 전송 — 다음 게임 준비 상태 초기화
      try {
        _client?.sendMessage(
          SetReadyMessage(playerId: playerId, isReady: false).toEnvelope(),
        );
      } catch (_) {}
    }
    setState(() {
      _phase = _NodePhase.lobby;
      _playerView = null;
      _gameState = null;
      _isReady = false;
      _actionPending = false;
      _autoSkipWarning = null;
    });
  }

  void _disconnect() {
    final identity = _identity;
    if (identity != null) {
      _client?.sendMessage(
        JoinMessage.leave(
          playerId: _assignedPlayerId ?? identity.deviceId,
        ).toEnvelope(),
      );
    }
    _client?.disconnect();
    // Deliberate disconnect — clear the saved token so we don't accidentally
    // reconnect to a stale session on next launch.
    PlayerIdentity.clearReconnectToken();
    setState(() {
      _client = null;
      _phase = _NodePhase.discovery;
      _assignedPlayerId = null;
      _reconnectToken = null;
      _savedServerUrl = null;
      _gameState = null;
      _playerView = null;
      _isReady = false;
      _reconnectAttempts = 0;
      _connState = WsConnectionState.connected;
      _actionPending = false;
      _lobbyState = const LobbyStateMessage(players: [], canStart: false);
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  /// Shows a confirmation dialog when the user tries to leave via back button.
  /// Returns true if the user confirmed they want to leave.
  Future<bool> _confirmLeave() async {
    if (_phase == _NodePhase.discovery) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방에서 나가기'),
        content: Text(
          _phase == _NodePhase.inGame
              ? '게임이 진행 중이에요. 나가면 자리가 유지돼요.\n나중에 이어하기로 돌아올 수 있어요.'
              : '대기실에서 나갈까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('나가기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await _confirmLeave();
        if (leave && mounted) {
          if (_phase != _NodePhase.discovery) _disconnect();
          navigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('board-go'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Nickname',
            onPressed: _showNicknameDialog,
          ),
          if (_phase != _NodePhase.discovery)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Disconnect',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: Stack(
        children: [
          switch (_phase) {
            _NodePhase.discovery => _buildDiscovery(),
            _NodePhase.lobby => _buildLobby(),
            _NodePhase.inGame => _buildGameUI(),
          },
          // Auto-skip warning banner (shown when an offline player's turn is
          // counting down to an automatic END_TURN).
          if (_autoSkipWarning != null) _buildAutoSkipBanner(_autoSkipWarning!),
          // Emote overlays — shown on top of all other content.
          ..._emoteOverlays.asMap().entries.map(
                (entry) => _buildEmoteOverlay(entry.value, entry.key),
              ),
          // Chat overlays — shown above emote overlays.
          ..._chatOverlays.asMap().entries.map(
                (entry) => _buildChatOverlay(entry.value, entry.key),
              ),
          // Sprint 3: disconnection overlay (only when not in discovery).
          if (_phase != _NodePhase.discovery &&
              _connState != WsConnectionState.connected)
            _buildConnectionOverlay(),
        ],
      ),
    ), // Scaffold
    ); // PopScope
  }

  // ---------------------------------------------------------------------------
  // Sprint 3: connection overlay
  // ---------------------------------------------------------------------------

  Widget _buildAutoSkipBanner(Map<String, dynamic> warning) {
    final nickname = warning['nickname'] as String? ?? '?';
    final seconds = warning['skipInSeconds'] as int? ?? 60;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.orange.shade700,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.timer, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$nickname 오프라인 — ${seconds}초 후 자동 스킵',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionOverlay() {
    final isReconnecting = _connState == WsConnectionState.reconnecting;
    final maxAttempts = _client?.maxReconnectAttempts ?? 0;
    final attemptsLabel = maxAttempts <= 0 ? '무제한' : '$maxAttempts';
    final label = isReconnecting
        ? '재접속 시도 중... ($_reconnectAttempts/$attemptsLabel)'
        : '연결 끊김, 재접속 중...';

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Phase builders
  // ---------------------------------------------------------------------------

  Widget _buildDiscovery() {
    final savedUrl = _savedServerUrl;
    if (savedUrl == null) {
      return DiscoveryScreen(onServerSelected: _connectTo);
    }
    return Column(
      children: [
        _buildResumeCard(savedUrl),
        Expanded(child: DiscoveryScreen(onServerSelected: _connectTo)),
      ],
    );
  }

  /// Banner shown when a previous session's reconnect token is available.
  Widget _buildResumeCard(String serverUrl) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.play_circle_filled,
                color: Colors.green.shade700, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '이전 게임이 진행 중이에요',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  Text(
                    serverUrl.replaceFirst('ws://', '').replaceFirst('/ws', ''),
                    style: TextStyle(
                        fontSize: 12, color: Colors.green.shade600),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _connectTo(serverUrl),
              child: const Text('이어하기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobby() {
    return LobbyWaitingScreen(
      localPlayerId: _assignedPlayerId ?? _identity?.deviceId ?? '',
      lobbyState: _lobbyState,
      isReady: _isReady,
      onReadyToggle: _sendReadyToggle,
    );
  }

  Widget _buildGameUI() {
    final pv = _playerView;

    // Sprint 2: use PlayerView when available.
    if (pv != null) {
      return _buildPlayerViewUI(pv);
    }

    // Legacy fallback (pre-Sprint 2 servers).
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_gameState != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Turn: ${_gameState!['turn']} — Active: ${_gameState!['activePlayerId']}',
                ),
              ),
            ),
          const SizedBox(height: 24),
          PlayerActionWidget(
            actionType: 'PLAY_CARD',
            label: 'Play Card',
            onAction: () => _sendAction('PLAY_CARD', {'cardId': 'unknown'}),
          ),
          const SizedBox(height: 8),
          PlayerActionWidget(
            actionType: 'DRAW_CARD',
            label: 'Draw Card',
            onAction: () => _sendAction('DRAW_CARD'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerViewUI(PlayerView pv) {
    if (pv.phase == SessionPhase.finished) {
      return _buildGameOverUI(pv);
    }

    final allowedTypes = pv.allowedActions.map((a) => a.actionType).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Turn indicator.
        _buildTurnBanner(pv),
        const Divider(height: 1),
        // Hand.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: HandWidget(
            hand: pv.hand,
            // Disable card taps while an action is awaiting server response.
            allowedTypes: _actionPending ? const {} : allowedTypes,
            onCardTap: _actionPending
                ? null
                : (cardId) => _sendAction('PLAY_CARD', {'cardId': cardId}),
          ),
        ),
        const Divider(height: 1),
        // Non-card actions (DRAW_CARD, END_TURN).
        AllowedActionsWidget(
          allowedActions: pv.allowedActions,
          disabled: _actionPending,
          onActionTap: (action) =>
              _sendAction(action.actionType, action.params),
        ),
        // Emote button row — always visible during game.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _buildEmoteBar(),
        ),
        const Spacer(),
        // Score summary.
        _buildScoreSummary(pv),
      ],
    );
  }

  /// Row of quick-reaction buttons + chat button displayed during the game.
  Widget _buildEmoteBar() {
    const emotes = SimpleCardGameEmote.all;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ...emotes.map(
          (emoji) => IconButton(
            onPressed: () => _sendNodeMessage(
              SimpleCardGameEmote.emote,
              payload: {'emoji': emoji},
            ),
            icon: Text(emoji, style: const TextStyle(fontSize: 22)),
            tooltip: emoji,
          ),
        ),
        IconButton(
          onPressed: _showChatDialog,
          icon: const Icon(Icons.chat_bubble_outline),
          tooltip: '메시지 전송',
        ),
      ],
    );
  }

  /// Shows a text input dialog and sends a [SimpleCardGameEmote.chat] message.
  Future<void> _showChatDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메시지 전송'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '최대 20자'),
          maxLength: SimpleCardGameEmote.chatMaxLength,
          autofocus: true,
          onSubmitted: (_) => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('전송'),
          ),
        ],
      ),
    );

    final text = controller.text.trim();
    if (text.isNotEmpty && text.length <= SimpleCardGameEmote.chatMaxLength) {
      _sendNodeMessage(SimpleCardGameEmote.chat, payload: {'text': text});
    }
  }

  /// Floating overlay chip for a received emote.
  ///
  /// Stacked vertically by [index] so multiple simultaneous emotes do not
  /// overlap each other.
  Widget _buildEmoteOverlay(
    ({String emoji, String fromNickname}) data,
    int index,
  ) {
    return Positioned(
      bottom: 120 + index * 56.0,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(data.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 8),
              Text(
                data.fromNickname,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating chat bubble for a received chat message.
  ///
  /// Stacked vertically by [index] so multiple simultaneous messages do not
  /// overlap each other.  Positioned above the emote overlay area.
  Widget _buildChatOverlay(
    ({String text, String fromNickname}) data,
    int index,
  ) {
    return Positioned(
      bottom: 240 + index * 56.0,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.fromNickname,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameOverUI(PlayerView pv) {
    return GameOverWidget(playerView: pv, onMainMenu: _returnToLobby);
  }

  Widget _buildTurnBanner(PlayerView pv) {
    final isMyTurn = pv.allowedActions.isNotEmpty;
    final ts = pv.turnState;

    return Container(
      color: isMyTurn ? Colors.blue.shade50 : Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            isMyTurn ? Icons.play_arrow : Icons.hourglass_top,
            color: isMyTurn ? Colors.blue : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isMyTurn ? '내 차례' : '대기 중...',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isMyTurn ? Colors.blue.shade700 : Colors.grey.shade600,
            ),
          ),
          if (ts != null) ...[
            const Spacer(),
            Text(
              'Round ${ts.round}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreSummary(PlayerView pv) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: pv.scores.entries.map((e) {
          final isSelf = e.key == pv.playerId;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSelf ? 'You' : e.key,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelf ? FontWeight.bold : FontWeight.normal,
                  color: isSelf ? Colors.blue.shade700 : Colors.black87,
                ),
              ),
              Text(
                '${e.value} pts',
                style: TextStyle(
                  fontWeight: isSelf ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
