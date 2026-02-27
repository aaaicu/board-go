import 'package:flutter/material.dart';

/// Renders a player's private hand as a row of tappable card widgets.
///
/// When [isMyTurn] is false (i.e., [allowedTypes] is empty), all cards are
/// rendered semi-transparent to indicate they cannot be interacted with.
class HandWidget extends StatelessWidget {
  /// The card ID strings belonging to this player.
  final List<String> hand;

  /// The set of action types currently allowed for this player.
  /// An empty set means it is not this player's turn.
  final Set<String> allowedTypes;

  /// Called when the player taps a card.  The card ID is passed as the argument.
  final void Function(String cardId)? onCardTap;

  const HandWidget({
    super.key,
    required this.hand,
    required this.allowedTypes,
    this.onCardTap,
  });

  bool get _isMyTurn => allowedTypes.contains('PLAY_CARD');

  @override
  Widget build(BuildContext context) {
    if (hand.isEmpty) {
      return const Center(
        child: Text(
          'No cards in hand',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: hand.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cardId = hand[index];
          return _CardTile(
            cardId: cardId,
            enabled: _isMyTurn,
            onTap: _isMyTurn ? () => onCardTap?.call(cardId) : null,
          );
        },
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final String cardId;
  final bool enabled;
  final VoidCallback? onTap;

  const _CardTile({
    required this.cardId,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final parts = cardId.split('-');
    final rank = parts.isNotEmpty ? parts[0] : cardId;
    final suit = parts.length > 1 ? parts[1] : '';

    final suitColor = (suit == 'hearts' || suit == 'diamonds')
        ? Colors.red
        : Colors.black87;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: enabled ? 3 : 1,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: enabled ? Colors.blue.shade300 : Colors.grey.shade300,
            ),
          ),
          child: SizedBox(
            width: 60,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    rank,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: suitColor,
                    ),
                  ),
                  Text(
                    _suitSymbol(suit),
                    style: TextStyle(fontSize: 14, color: suitColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _suitSymbol(String suit) => switch (suit) {
        'clubs' => '♣',
        'diamonds' => '♦',
        'hearts' => '♥',
        'spades' => '♠',
        _ => suit,
      };
}
