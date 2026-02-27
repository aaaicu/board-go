import 'package:flutter/material.dart';

import '../../shared/messages/lobby_state_message.dart';

/// Screen displayed on a player's phone while waiting in the lobby.
///
/// The player can toggle their own ready state via the button.
/// The current player list (nickname + ready status) is shown.
/// A "게임 호스트를 기다리는 중..." notice is displayed at the top.
class LobbyWaitingScreen extends StatelessWidget {
  final String localPlayerId;
  final LobbyStateMessage lobbyState;
  final bool isReady;
  final ValueChanged<bool> onReadyToggle; // passes new isReady value

  const LobbyWaitingScreen({
    super.key,
    required this.localPlayerId,
    required this.lobbyState,
    required this.isReady,
    required this.onReadyToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Scrollable content area ---
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Waiting notice ---
                const Card(
                  color: Color(0xFFFFF9C4),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.hourglass_top, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '게임 호스트를 기다리는 중...',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // --- Player list ---
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '플레이어 (${lobbyState.players.length}명)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Divider(),
                        if (lobbyState.players.isEmpty)
                          const Text('플레이어 목록이 없습니다.')
                        else
                          ...lobbyState.players.map(
                            (p) => _PlayerRow(
                              info: p,
                              isMe: p.playerId == localPlayerId,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // --- Ready toggle button — always pinned to the bottom ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: () => onReadyToggle(!isReady),
            icon: Icon(isReady ? Icons.cancel : Icons.check_circle),
            label: Text(
              isReady ? '준비 취소' : '준비 완료',
              style: const TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isReady ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single row in the waiting lobby player list.
class _PlayerRow extends StatelessWidget {
  final LobbyStatePlayerInfo info;
  final bool isMe;

  const _PlayerRow({required this.info, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            info.isConnected ? Icons.person : Icons.person_off,
            size: 18,
            color: info.isConnected ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              isMe ? '${info.nickname} (나)' : info.nickname,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        isMe ? FontWeight.bold : FontWeight.normal,
                  ),
            ),
          ),
          Icon(
            info.isReady ? Icons.check_circle : Icons.radio_button_unchecked,
            color: info.isReady ? Colors.green : Colors.orange,
            size: 18,
          ),
        ],
      ),
    );
  }
}
