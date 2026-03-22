import 'package:flutter/material.dart';

import '../../shared/messages/lobby_state_message.dart';
import '../shared/app_theme.dart';
import '../shared/widgets/board_card.dart';
import '../shared/widgets/primary_button.dart';
import '../shared/widgets/status_chip.dart';

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
                // --- Waiting notice: secondary_container banner ---
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.hourglass_top_rounded,
                        color: AppTheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '게임 호스트를 기다리는 중...',
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // --- Section header ---
                Text(
                  '플레이어 (${lobbyState.players.length}명)',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),

                // --- Player list ---
                if (lobbyState.players.isEmpty)
                  const Text(
                    '플레이어 목록이 없습니다.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.onSurfaceMuted,
                    ),
                  )
                else
                  ...lobbyState.players.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PlayerRow(
                        info: p,
                        isMe: p.playerId == localPlayerId,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // --- Ready toggle button — always pinned to the bottom ---
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: isReady
              ? _CancelReadyButton(onPressed: () => onReadyToggle(false))
              : PrimaryButton(
                  label: '준비 완료',
                  icon: Icons.check_circle_outline_rounded,
                  onPressed: () => onReadyToggle(true),
                ),
        ),
      ],
    );
  }
}

/// "준비 취소" button uses danger styling.
class _CancelReadyButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _CancelReadyButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: AppTheme.errorContainer,
        borderRadius: BorderRadius.circular(9999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9999),
          child: const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cancel_outlined, color: AppTheme.error, size: 20),
                SizedBox(width: 8),
                Text(
                  '준비 취소',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return BoardCard(
      backgroundColor: isMe
          ? AppTheme.primaryContainer
          : AppTheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 16,
      child: Row(
        children: [
          // Avatar circle
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMe
                  ? AppTheme.primary.withValues(alpha: 0.2)
                  : AppTheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Text(
                info.nickname.isNotEmpty
                    ? info.nickname[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isMe ? AppTheme.primary : AppTheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OnlineDot(isOnline: info.isConnected),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isMe ? '${info.nickname} (나)' : info.nickname,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                fontWeight: isMe ? FontWeight.w700 : FontWeight.w400,
                color: isMe ? AppTheme.primary : AppTheme.onSurface,
              ),
            ),
          ),
          StatusChip(
            status: info.isReady ? ChipStatus.ready : ChipStatus.waiting,
          ),
        ],
      ),
    );
  }
}
