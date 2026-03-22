import 'package:flutter/material.dart';

import '../../shared/game_pack/views/board_view.dart';
import '../../shared/game_session/session_phase.dart';
import '../shared/app_theme.dart';
import 'stockpile_board_widget.dart';

/// Renders the shared game board visible on the iPad (GameBoard) during
/// the [SessionPhase.inGame] phase.
///
/// Receives a [BoardView] — which contains no player hand data — and
/// displays public game information: turn state, scores, deck, discard pile,
/// and recent action log.
///
/// Sprint 3 addition:
///   - [offlinePlayerIds]: set of player IDs that are currently disconnected.
///     Disconnected players are rendered in grey with an "(오프라인)" badge.
class GameBoardPlayScreen extends StatelessWidget {
  final BoardView boardView;

  /// Optional map from playerId → display name for friendlier labels.
  final Map<String, String> playerNames;

  /// Player IDs that are currently offline (disconnected but not removed).
  final Set<String> offlinePlayerIds;

  /// Optional server status widget provided by the platform.
  ///
  /// Non-null when the host has toggled the server-status overlay on.
  /// Game-pack board widgets should embed this wherever it fits their layout,
  /// or pass it down to a sub-widget.  When null the widget is hidden.
  final Widget? serverStatusWidget;

  const GameBoardPlayScreen({
    super.key,
    required this.boardView,
    this.playerNames = const {},
    this.offlinePlayerIds = const {},
    this.serverStatusWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Stockpile game pack: delegate to the Stockpile-specific board widget.
    if (boardView.data['packId'] == 'stockpile') {
      return StockpileBoardWidget(
        boardView: boardView,
        playerNames: playerNames,
        serverStatusWidget: serverStatusWidget,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (serverStatusWidget != null) serverStatusWidget!,
        _buildTurnHeader(context),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildCenterPanel()),
              const VerticalDivider(width: 1),
              SizedBox(width: 240, child: _buildLogPanel()),
            ],
          ),
        ),
        const Divider(height: 1),
        _buildDeckRow(context),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Turn header
  // ---------------------------------------------------------------------------

  Widget _buildTurnHeader(BuildContext context) {
    final ts = boardView.turnState;
    final activeId = ts?.activePlayerId ?? '';
    final activeName = playerNames[activeId] ?? activeId;
    final round = ts?.round ?? 1;

    return Container(
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            'Round $round',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 24),
          if (ts != null) ...[
            const Icon(Icons.play_arrow, size: 18),
            const SizedBox(width: 4),
            Text(
              activeName,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              "'s turn",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          const Spacer(),
          if (boardView.phase == SessionPhase.finished)
            Chip(
              label: const Text(
                'Game Over',
                style: TextStyle(color: AppTheme.error),
              ),
              backgroundColor: AppTheme.errorContainer,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Score board — Sprint 3: offline badge
  // ---------------------------------------------------------------------------

  Widget _buildCenterPanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Scores',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.onSurface)),
          const SizedBox(height: 8),
          ...boardView.scores.entries.map((e) {
            final name = playerNames[e.key] ?? e.key;
            final isActive =
                boardView.turnState?.activePlayerId == e.key;
            final isOffline = offlinePlayerIds.contains(e.key);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  if (isActive && !isOffline)
                    const Icon(Icons.arrow_right, size: 18, color: AppTheme.primary)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isOffline
                                ? AppTheme.onSurfaceMuted
                                : AppTheme.onSurface,
                          ),
                        ),
                        if (isOffline) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '(오프라인)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '${e.value} pts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOffline
                          ? AppTheme.onSurfaceMuted
                          : AppTheme.onSurface,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Deck / discard row
  // ---------------------------------------------------------------------------

  Widget _buildDeckRow(BuildContext context) {
    final topCard = boardView.discardPile.isNotEmpty
        ? boardView.discardPile.last
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildPileCard(
            context,
            label: 'Deck',
            subtitle: '${boardView.deckRemaining} cards',
            icon: Icons.layers,
            color: AppTheme.surfaceContainerHigh,
          ),
          const SizedBox(width: 16),
          _buildPileCard(
            context,
            label: 'Discard',
            subtitle: topCard ?? '(empty)',
            icon: Icons.do_not_disturb_on,
            color: AppTheme.secondaryContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildPileCard(
    BuildContext context, {
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                  Text(subtitle, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Action log
  // ---------------------------------------------------------------------------

  Widget _buildLogPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('Recent Actions',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.onSurface)),
          ),
          Expanded(
            child: ListView(
              reverse: true,
              children: boardView.recentLog.reversed
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        e.description,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
