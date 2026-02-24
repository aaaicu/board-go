import 'dart:convert';

import 'package:flutter/material.dart';

import '../shared/ws_client.dart';
import '../shared/player_identity.dart';
import '../../shared/messages/ws_message.dart';
import '../../shared/messages/action_message.dart';
import '../../shared/messages/join_message.dart';
import '../../shared/messages/state_update_message.dart';
import 'discovery_screen.dart';
import 'player_action_widget.dart';

/// The main screen displayed on a player's phone.
///
/// Shows [DiscoveryScreen] until the player connects to a GameBoard server,
/// then switches to the player action UI.
///
/// Player identity (stable UUID + nickname) is loaded asynchronously from
/// [PlayerIdentity] on [initState]. Until it is ready the screen renders
/// normally — the identity is only needed at the moment of connection.
class GameNodeScreen extends StatefulWidget {
  const GameNodeScreen({super.key});

  @override
  State<GameNodeScreen> createState() => _GameNodeScreenState();
}

class _GameNodeScreenState extends State<GameNodeScreen> {
  WsClient? _client;
  bool _connected = false;
  bool _disposing = false;
  Map<String, dynamic>? _gameState;

  /// Loaded asynchronously in [initState]; null while loading.
  PlayerIdentity? _identity;

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
    if (identity == null) return; // Identity not yet loaded.

    final client = WsClient(
      uri: Uri.parse(wsUrl),
      onConnectionStateChange: (connected) {
        if (mounted && !_disposing) setState(() => _connected = connected);
      },
    );

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

    // Listen for state updates.
    client.messages.listen((raw) {
      try {
        final msg = WsMessage.fromJson(
          jsonDecode(raw as String) as Map<String, dynamic>,
        );
        if (msg.type == WsMessageType.stateUpdate) {
          final update = StateUpdateMessage.fromEnvelope(msg);
          if (mounted) setState(() => _gameState = update.state);
        }
      } catch (_) {
        // Ignore malformed messages.
      }
    });

    setState(() {
      _client = client;
      _connected = true;
    });

    // Announce ourselves with the persistent UUID and chosen nickname.
    client.sendMessage(
      JoinMessage.join(
        playerId: identity.deviceId,
        displayName: identity.nickname,
      ).toEnvelope(),
    );
  }

  void _sendAction(String actionType, [Map<String, dynamic> data = const {}]) {
    final identity = _identity;
    if (identity == null) return;

    _client?.sendMessage(
      ActionMessage(
        playerId: identity.deviceId,
        actionType: actionType,
        data: data,
      ).toEnvelope(),
    );
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
          // Edit nickname — always accessible so players can change their name
          // before and after connecting.
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Nickname',
            onPressed: _showNicknameDialog,
          ),
          if (_connected)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Disconnect',
              onPressed: () {
                final identity = _identity;
                if (identity != null) {
                  _client?.sendMessage(
                    JoinMessage.leave(playerId: identity.deviceId).toEnvelope(),
                  );
                }
                _client?.disconnect();
                setState(() {
                  _client = null;
                  _connected = false;
                  _gameState = null;
                });
              },
            ),
        ],
      ),
      body: _connected ? _buildGameUI() : _buildDiscovery(),
    );
  }

  Widget _buildDiscovery() {
    return DiscoveryScreen(onServerSelected: _connectTo);
  }

  Widget _buildGameUI() {
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
}
