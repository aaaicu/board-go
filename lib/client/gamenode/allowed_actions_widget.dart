import 'package:flutter/material.dart';

import '../../shared/game_pack/views/allowed_action.dart';

/// Renders the list of actions this player is currently allowed to take.
///
/// When [allowedActions] is empty it shows a "waiting" message indicating it
/// is another player's turn.  Otherwise it renders one [ElevatedButton] per
/// non-PLAY_CARD action (PLAY_CARD actions are handled via [HandWidget]).
class AllowedActionsWidget extends StatelessWidget {
  final List<AllowedAction> allowedActions;

  /// Called when the player taps a non-card action (DRAW_CARD / END_TURN).
  final void Function(AllowedAction action)? onActionTap;

  const AllowedActionsWidget({
    super.key,
    required this.allowedActions,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (allowedActions.isEmpty) {
      return const _WaitingBanner();
    }

    // Filter out PLAY_CARD actions — those are triggered through HandWidget.
    final nonCardActions =
        allowedActions.where((a) => a.actionType != 'PLAY_CARD').toList();

    if (nonCardActions.isEmpty) {
      // Only PLAY_CARD available — handled by hand.
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: nonCardActions.map((action) {
          return _ActionButton(
            action: action,
            onTap: () => onActionTap?.call(action),
          );
        }).toList(),
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  const _WaitingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            '상대방 턴',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final AllowedAction action;
  final VoidCallback onTap;

  const _ActionButton({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEndTurn = action.actionType == 'END_TURN';
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isEndTurn ? Colors.orange.shade100 : null,
        foregroundColor: isEndTurn ? Colors.orange.shade800 : null,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      icon: Icon(
        isEndTurn ? Icons.skip_next : Icons.add_card,
        size: 18,
      ),
      label: Text(action.label),
      onPressed: onTap,
    );
  }
}
