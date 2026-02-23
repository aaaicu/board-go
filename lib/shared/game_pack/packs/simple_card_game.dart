import '../game_pack_interface.dart';
import '../game_state.dart';
import '../player_action.dart';

// ---------------------------------------------------------------------------
// Card definitions
// ---------------------------------------------------------------------------

const List<String> _suits = ['♠', '♥', '♦', '♣'];
const List<String> _ranks = [
  'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K',
];

List<String> _buildDeck() {
  final deck = <String>[
    for (final suit in _suits)
      for (final rank in _ranks) '$rank$suit',
  ];
  deck.shuffle();
  return deck;
}

// ---------------------------------------------------------------------------
// SimpleCardGame
// ---------------------------------------------------------------------------

/// A minimal [GamePackInterface] implementation.
///
/// Rules:
/// - Each player starts with a hand of N cards (default 5) drawn from a
///   shuffled standard 52-card deck.
/// - On their turn a player may either:
///   - **PLAY_CARD** — place one card from their hand onto the discard pile.
///   - **DRAW_CARD** — draw the top card from the deck into their hand.
/// - After each action the turn advances to the next player.
/// - Playing out-of-turn or playing/drawing cards that don't exist is invalid.
class SimpleCardGame implements GamePackInterface {
  GameState _state = GameState(
    gameId: '',
    turn: 0,
    activePlayerId: '',
    data: {},
  );

  /// Exposes the latest game state (used in tests).
  GameState get currentState => _state;

  @override
  Future<void> initialize(GameState initialState) async {
    final playerIds =
        List<String>.from(initialState.data['playerIds'] as List? ?? []);
    final handSize = (initialState.data['handSize'] as int?) ?? 5;

    final deck = _buildDeck();
    final hands = <String, List<String>>{};

    for (final playerId in playerIds) {
      hands[playerId] = deck.sublist(0, handSize);
      deck.removeRange(0, handSize);
    }

    _state = initialState.copyWith(
      data: {
        ...initialState.data,
        'deck': deck,
        'hands': hands,
        'discardPile': <String>[],
        'scores': {for (final id in playerIds) id: 0},
      },
    );
  }

  @override
  bool validateAction(PlayerAction action, GameState currentState) {
    // Only the active player may act.
    if (action.playerId != currentState.activePlayerId) return false;

    switch (action.type) {
      case 'PLAY_CARD':
        final cardId = action.data['cardId'] as String?;
        if (cardId == null) return false;
        final hand = _handOf(action.playerId, currentState);
        return hand.contains(cardId);

      case 'DRAW_CARD':
        final deck = currentState.data['deck'] as List;
        return deck.isNotEmpty;

      default:
        return false;
    }
  }

  @override
  GameState processAction(PlayerAction action, GameState currentState) {
    return switch (action.type) {
      'PLAY_CARD' => _applyPlayCard(action, currentState),
      'DRAW_CARD' => _applyDrawCard(action, currentState),
      _ => currentState,
    };
  }

  @override
  Future<void> dispose() async {}

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  List<String> _handOf(String playerId, GameState state) {
    final hands = state.data['hands'] as Map;
    return List<String>.from(hands[playerId] as List? ?? []);
  }

  List<String> _deckOf(GameState state) =>
      List<String>.from(state.data['deck'] as List);

  List<String> _discardOf(GameState state) =>
      List<String>.from(state.data['discardPile'] as List);

  Map<String, dynamic> _handsMap(GameState state) =>
      Map<String, dynamic>.from(state.data['hands'] as Map);

  String _nextPlayer(GameState state) {
    final players =
        List<String>.from(state.data['playerIds'] as List? ?? [state.activePlayerId]);
    final idx = players.indexOf(state.activePlayerId);
    return players[(idx + 1) % players.length];
  }

  GameState _advanceTurn(GameState state) => state.copyWith(
        turn: state.turn + 1,
        activePlayerId: _nextPlayer(state),
      );

  GameState _applyPlayCard(PlayerAction action, GameState state) {
    final cardId = action.data['cardId'] as String;
    final hand = _handOf(action.playerId, state)..remove(cardId);
    final discard = _discardOf(state)..add(cardId);
    final hands = _handsMap(state)..[action.playerId] = hand;

    final newState = state.copyWith(
      data: {
        ...state.data,
        'hands': hands,
        'discardPile': discard,
      },
    );
    return _advanceTurn(newState);
  }

  GameState _applyDrawCard(PlayerAction action, GameState state) {
    final deck = _deckOf(state);
    final drawn = deck.removeAt(0);
    final hand = _handOf(action.playerId, state)..add(drawn);
    final hands = _handsMap(state)..[action.playerId] = hand;

    final newState = state.copyWith(
      data: {
        ...state.data,
        'deck': deck,
        'hands': hands,
      },
    );
    return _advanceTurn(newState);
  }
}
