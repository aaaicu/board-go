import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../shared/ws_client.dart';
import '../shared/player_identity.dart';
import '../../shared/game_pack/views/allowed_action.dart';
import '../../shared/game_pack/views/player_view.dart';
import '../../shared/messages/action_message.dart';
import '../../shared/messages/join_message.dart';
import '../../shared/messages/join_room_ack_message.dart';
import '../../shared/messages/lobby_state_message.dart';
import '../../shared/messages/player_view_message.dart';
import '../../shared/messages/set_ready_message.dart';
import '../../shared/messages/state_update_message.dart';
import '../../shared/messages/ws_message.dart';
import 'allowed_actions_widget.dart';
import 'discovery_screen.dart';
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

  // ---------------------------------------------------------------------------
  // Sprint 3: connection state
  // ---------------------------------------------------------------------------

  WsConnectionState _connState = WsConnectionState.connected;
  int _reconnectAttempts = 0;

  @override
  void initState() {
    super.initState();
    PlayerIdentity.load().then((identity) {
      if (mounted) setState(() => _identity = identity);
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
        });

      // BOARD_VIEW is for the GameBoard (iPad); GameNode ignores it.
      case WsMessageType.boardView:
        break;

      default:
        break;
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
    final identity = _identity;
    if (identity == null) return;

    _client?.sendMessage(
      ActionMessage(
        playerId: _assignedPlayerId ?? identity.deviceId,
        actionType: actionType,
        data: data,
      ).toEnvelope(),
    );
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
    setState(() {
      _client = null;
      _phase = _NodePhase.discovery;
      _assignedPlayerId = null;
      _gameState = null;
      _playerView = null;
      _isReady = false;
      _reconnectAttempts = 0;
      _connState = WsConnectionState.connected;
      _lobbyState = const LobbyStateMessage(players: [], canStart: false);
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          // Sprint 3: disconnection overlay (only when not in discovery).
          if (_phase != _NodePhase.discovery &&
              _connState != WsConnectionState.connected)
            _buildConnectionOverlay(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sprint 3: connection overlay
  // ---------------------------------------------------------------------------

  Widget _buildConnectionOverlay() {
    final isReconnecting = _connState == WsConnectionState.reconnecting;
    final label = isReconnecting
        ? '재접속 시도 중... ($_reconnectAttempts/${_client?.maxReconnectAttempts ?? 5})'
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
    return DiscoveryScreen(onServerSelected: _connectTo);
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
            allowedTypes: allowedTypes,
            onCardTap: (cardId) =>
                _sendAction('PLAY_CARD', {'cardId': cardId}),
          ),
        ),
        const Divider(height: 1),
        // Non-card actions (DRAW_CARD, END_TURN).
        AllowedActionsWidget(
          allowedActions: pv.allowedActions,
          onActionTap: (action) =>
              _sendAction(action.actionType, action.params),
        ),
        const Spacer(),
        // Score summary.
        _buildScoreSummary(pv),
      ],
    );
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
