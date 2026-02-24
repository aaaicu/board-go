import 'dart:convert';

import 'package:flutter/material.dart';

import '../shared/ws_client.dart';
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
  final String _playerId =
      'player-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void dispose() {
    _disposing = true;
    _client?.dispose();
    super.dispose();
  }

  Future<void> _connectTo(String wsUrl) async {
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

    // Announce ourselves. Use the last 4 digits of the epoch-based playerId as
    // a short unique suffix so every device gets a distinct display name.
    client.sendMessage(
      JoinMessage.join(
        playerId: _playerId,
        displayName: 'Player#${_playerId.substring(_playerId.length - 4)}',
      ).toEnvelope(),
    );
  }

  void _sendAction(String actionType, [Map<String, dynamic> data = const {}]) {
    _client?.sendMessage(
      ActionMessage(
        playerId: _playerId,
        actionType: actionType,
        data: data,
      ).toEnvelope(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('board-go'),
        actions: [
          if (_connected)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Disconnect',
              onPressed: () {
                _client?.sendMessage(
                  JoinMessage.leave(playerId: _playerId).toEnvelope(),
                );
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
