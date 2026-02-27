/// Immutable definition of a single playing card, parsed from `cards.json`.
///
/// Card definitions are pure data — they describe what a card is, not the
/// runtime state of a card in a game session.  The [id] field is the stable
/// identifier used throughout [GameSessionState] (e.g. in `hands`, `deck`,
/// and `discardPile` lists).
class CardDefinition {
  /// Stable, unique identifier for this card (e.g. `'clubs_A'`, `'spades_K'`).
  final String id;

  /// Suit name: one of `'clubs'`, `'diamonds'`, `'hearts'`, `'spades'`.
  final String suit;

  /// Rank label: one of `'A'`, `'2'`–`'10'`, `'J'`, `'Q'`, `'K'`.
  final String rank;

  /// Numeric value of the card.
  /// Ace = 1; 2–10 = face value; J = 11, Q = 12, K = 13.
  final int value;

  /// Localised (Korean) display name shown in the UI (e.g. `'클럽 A'`).
  final String displayName;

  const CardDefinition({
    required this.id,
    required this.suit,
    required this.rank,
    required this.value,
    required this.displayName,
  });

  factory CardDefinition.fromJson(Map<String, dynamic> json) => CardDefinition(
        id: json['id'] as String,
        suit: json['suit'] as String,
        rank: json['rank'] as String,
        value: json['value'] as int,
        displayName: json['displayName'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'suit': suit,
        'rank': rank,
        'value': value,
        'displayName': displayName,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardDefinition && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CardDefinition(id: $id, suit: $suit, rank: $rank, value: $value)';
}
