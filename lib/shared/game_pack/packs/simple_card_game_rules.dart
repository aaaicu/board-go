import 'dart:math';

import '../../game_session/game_log_entry.dart';
import '../../game_session/game_session_state.dart';
import '../../game_session/session_phase.dart';
import '../../game_session/turn_state.dart';
import '../../game_session/turn_step.dart';
import '../card_definition.dart';
import '../game_pack_rules.dart';
import '../game_state.dart';
import '../player_action.dart';
import '../views/allowed_action.dart';
import '../views/board_view.dart';
import '../views/player_view.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String _kPackId = 'simple_card_game';
const int _kHandSize = 5;
const int _kMaxRounds = 3;
const int _kMaxDiscardDisplay = 5;
const int _kMaxRecentLog = 10;

const List<String> _kSuits = ['clubs', 'diamonds', 'hearts', 'spades'];
const List<String> _kRanks = [
  'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K',
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<String> _buildDeck({int? seed}) {
  final deck = <String>[
    for (final suit in _kSuits)
      for (final rank in _kRanks) '$rank-$suit',
  ];
  deck.shuffle(seed != null ? Random(seed) : Random());
  return deck;
}

Map<String, List<String>> _dealHands(
  List<String> playerOrder,
  List<String> deck,
) {
  final hands = <String, List<String>>{};
  for (final playerId in playerOrder) {
    hands[playerId] = List<String>.from(deck.sublist(0, _kHandSize));
    deck.removeRange(0, _kHandSize);
  }
  return hands;
}

// ---------------------------------------------------------------------------
// SimpleCardGameRules
// ---------------------------------------------------------------------------

/// Concrete [GamePackRules] implementation for the simple card game.
///
/// Game data is stored as plain Dart maps inside [GameSessionState.gameState.data]:
///   - `hands`:       Map<playerId, List<String>>
///   - `deck`:        List<String>
///   - `discardPile`: List<String>
///   - `scores`:      Map<playerId, int>
///
/// All methods are pure — no mutable instance state beyond [packId].
///
/// ## Card ID formats
///
/// When [cardDefinitions] is provided (loaded from `cards.json`), card IDs
/// follow the `'<suit>_<rank>'` format defined in the JSON (e.g. `'clubs_A'`).
///
/// When [cardDefinitions] is null the legacy `'<rank>-<suit>'` format is used
/// (e.g. `'A-clubs'`).  This preserves backward compatibility with all
/// existing tests that were written before Sprint 4.
class SimpleCardGameRules implements GamePackRules {
  /// Optional seed for the deck shuffle.  Inject in tests for determinism.
  final int? deckSeed;

  /// Optional external card definitions loaded from `cards.json`.
  ///
  /// When non-null, the deck is built from these definitions (in the order
  /// they appear in the list) before shuffling.  When null the legacy
  /// hardcoded deck is used — this preserves full backward compatibility
  /// with all pre-Sprint-4 tests.
  final List<CardDefinition>? _cardDefinitions;

  const SimpleCardGameRules({
    this.deckSeed,
    List<CardDefinition>? cardDefinitions,
  }) : _cardDefinitions = cardDefinitions;

  @override
  String get packId => _kPackId;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  GameSessionState createInitialGameState(GameSessionState sessionState) {
    final playerOrder = List<String>.from(sessionState.playerOrder);
    assert(playerOrder.isNotEmpty, 'Cannot start a game with no players');

    final deck = _buildActiveDeck();
    final hands = _dealHands(playerOrder, deck);

    final scores = <String, int>{for (final id in playerOrder) id: 0};

    final gameState = GameState(
      gameId: sessionState.sessionId,
      turn: 0,
      activePlayerId: playerOrder.first,
      data: {
        'hands': hands,
        'deck': deck,
        'discardPile': <String>[],
        'scores': scores,
      },
    );

    final turnState = TurnState(
      round: 1,
      turnIndex: 0,
      activePlayerId: playerOrder.first,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );

    return sessionState.copyWith(
      phase: SessionPhase.inGame,
      gameState: gameState,
      turnState: turnState,
      version: sessionState.version + 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  @override
  List<AllowedAction> getAllowedActions(
    GameSessionState state,
    String playerId,
  ) {
    if (state.phase != SessionPhase.inGame) return const [];
    final turnState = state.turnState;
    if (turnState == null) return const [];
    if (turnState.activePlayerId != playerId) return const [];

    final gameState = state.gameState;
    if (gameState == null) return const [];

    final hand = _handOf(playerId, gameState);
    final deck = _deckOf(gameState);

    final actions = <AllowedAction>[];

    // PLAY_CARD: one entry per card in hand.
    for (final cardId in hand) {
      actions.add(AllowedAction(
        actionType: 'PLAY_CARD',
        label: 'Play $cardId',
        params: {'cardId': cardId},
      ));
    }

    // DRAW_CARD: only if the deck has cards.
    if (deck.isNotEmpty) {
      actions.add(const AllowedAction(
        actionType: 'DRAW_CARD',
        label: 'Draw Card',
      ));
    }

    // END_TURN: always available during the main step.
    actions.add(const AllowedAction(
      actionType: 'END_TURN',
      label: 'End Turn',
    ));

    return actions;
  }

  // ---------------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------------

  @override
  GameSessionState applyAction(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    return switch (action.type) {
      'PLAY_CARD' => _applyPlayCard(state, playerId, action),
      'DRAW_CARD' => _applyDrawCard(state, playerId, action),
      'END_TURN' => _applyEndTurn(state, playerId),
      _ => state,
    };
  }

  // ---------------------------------------------------------------------------
  // End condition
  // ---------------------------------------------------------------------------

  @override
  ({bool ended, List<String> winnerIds}) checkGameEnd(
      GameSessionState state) {
    final gameState = state.gameState;
    final turnState = state.turnState;
    if (gameState == null || turnState == null) {
      return (ended: false, winnerIds: []);
    }

    final deck = _deckOf(gameState);
    final deckEmpty = deck.isEmpty;
    final roundsComplete = turnState.round > _kMaxRounds;

    if (!deckEmpty && !roundsComplete) {
      return (ended: false, winnerIds: []);
    }

    // Determine winner(s) by highest score.
    final scores = _scoresOf(gameState);
    final maxScore =
        scores.values.fold(0, (prev, s) => s > prev ? s : prev);
    final winners =
        scores.entries.where((e) => e.value == maxScore).map((e) => e.key).toList();

    return (ended: true, winnerIds: winners);
  }

  // ---------------------------------------------------------------------------
  // View builders
  // ---------------------------------------------------------------------------

  @override
  BoardView buildBoardView(GameSessionState state) {
    final gameState = state.gameState;
    final scores = gameState != null ? _scoresOf(gameState) : <String, int>{};
    final deckRemaining = gameState != null ? _deckOf(gameState).length : 0;
    final discardPile = gameState != null ? _discardOf(gameState) : <String>[];
    final topDiscard = discardPile.length > _kMaxDiscardDisplay
        ? discardPile.sublist(discardPile.length - _kMaxDiscardDisplay)
        : List<String>.from(discardPile);

    final recentLog = state.log.length > _kMaxRecentLog
        ? state.log.sublist(state.log.length - _kMaxRecentLog)
        : List<GameLogEntry>.from(state.log);

    return BoardView(
      phase: state.phase,
      scores: scores,
      turnState: state.turnState,
      deckRemaining: deckRemaining,
      discardPile: topDiscard,
      recentLog: recentLog,
      version: state.version,
    );
  }

  @override
  PlayerView buildPlayerView(GameSessionState state, String playerId) {
    final gameState = state.gameState;

    // Security: only fetch THIS player's hand.
    final hand =
        gameState != null ? _handOf(playerId, gameState) : <String>[];
    final scores =
        gameState != null ? _scoresOf(gameState) : <String, int>{};

    final allowedActions = getAllowedActions(state, playerId);

    return PlayerView(
      phase: state.phase,
      playerId: playerId,
      hand: hand,
      scores: scores,
      turnState: state.turnState,
      allowedActions: allowedActions,
      version: state.version,
    );
  }

  // ---------------------------------------------------------------------------
  // Private action helpers
  // ---------------------------------------------------------------------------

  GameSessionState _applyPlayCard(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final cardId = action.data['cardId'] as String?;
    if (cardId == null) return state;

    final gameState = state.gameState;
    if (gameState == null) return state;

    final hand = _handOf(playerId, gameState);
    if (!hand.contains(cardId)) return state;

    hand.remove(cardId);
    final discard = _discardOf(gameState)..add(cardId);
    final scores = Map<String, int>.from(_scoresOf(gameState));
    scores[playerId] = (scores[playerId] ?? 0) + 1;

    final updatedHands = _allHands(gameState)..[playerId] = hand;
    final newGameState = gameState.copyWith(data: {
      ...gameState.data,
      'hands': updatedHands,
      'discardPile': discard,
      'scores': scores,
    });

    final newTurnState = state.turnState!.copyWith(
      actionCountThisTurn: state.turnState!.actionCountThisTurn + 1,
    );

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'PLAY_CARD',
      description: '$playerId played $cardId',
    );

    return state
        .copyWith(
          gameState: newGameState,
          turnState: newTurnState,
        )
        .addLog(logEntry);
  }

  GameSessionState _applyDrawCard(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  ) {
    final gameState = state.gameState;
    if (gameState == null) return state;

    final deck = _deckOf(gameState);
    if (deck.isEmpty) return state;

    final drawn = deck.removeAt(0);
    final hand = _handOf(playerId, gameState)..add(drawn);
    final updatedHands = _allHands(gameState)..[playerId] = hand;

    final newGameState = gameState.copyWith(data: {
      ...gameState.data,
      'deck': deck,
      'hands': updatedHands,
    });

    final newTurnState = state.turnState!.copyWith(
      actionCountThisTurn: state.turnState!.actionCountThisTurn + 1,
    );

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'DRAW_CARD',
      description: '$playerId drew a card',
    );

    return state
        .copyWith(
          gameState: newGameState,
          turnState: newTurnState,
        )
        .addLog(logEntry);
  }

  GameSessionState _applyEndTurn(
    GameSessionState state,
    String playerId,
  ) {
    final gameState = state.gameState;
    final turnState = state.turnState;
    if (gameState == null || turnState == null) return state;

    final playerOrder = state.playerOrder;
    final nextIndex = (turnState.turnIndex + 1) % playerOrder.length;
    final isNewRound = nextIndex == 0;
    final nextRound = isNewRound ? turnState.round + 1 : turnState.round;
    final nextPlayerId = playerOrder[nextIndex];

    final newTurnState = TurnState(
      round: nextRound,
      turnIndex: nextIndex,
      activePlayerId: nextPlayerId,
      step: TurnStep.main,
      actionCountThisTurn: 0,
    );

    final newGameState = gameState.copyWith(
      activePlayerId: nextPlayerId,
      turn: gameState.turn + 1,
    );

    final logEntry = GameLogEntry(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      eventType: 'END_TURN',
      description: '$playerId ended turn',
    );

    return state
        .copyWith(
          gameState: newGameState,
          turnState: newTurnState,
        )
        .addLog(logEntry);
  }

  // ---------------------------------------------------------------------------
  // Private deck-building helpers
  // ---------------------------------------------------------------------------

  /// Returns a shuffled deck using the correct strategy for this instance:
  ///   - [_cardDefinitions] is set → use definition IDs (Sprint 4+ path).
  ///   - [_cardDefinitions] is null → use the legacy hardcoded format (pre-Sprint-4 path).
  List<String> _buildActiveDeck() {
    final defs = _cardDefinitions;
    if (defs != null && defs.isNotEmpty) {
      return _buildDeckFromDefinitions(defs, seed: deckSeed);
    }
    return _buildDeck(seed: deckSeed);
  }

  /// Builds a deck from injected [CardDefinition] objects and shuffles it.
  List<String> _buildDeckFromDefinitions(
    List<CardDefinition> definitions, {
    int? seed,
  }) {
    final deck = definitions.map((d) => d.id).toList();
    deck.shuffle(seed != null ? Random(seed) : Random());
    return deck;
  }

  // ---------------------------------------------------------------------------
  // Private data-access helpers (all return copies, never references)
  // ---------------------------------------------------------------------------

  List<String> _handOf(String playerId, GameState state) {
    final hands = state.data['hands'] as Map;
    return List<String>.from(hands[playerId] as List? ?? []);
  }

  Map<String, List<String>> _allHands(GameState state) {
    final raw = state.data['hands'] as Map;
    return raw.map(
      (k, v) => MapEntry(k as String, List<String>.from(v as List)),
    );
  }

  List<String> _deckOf(GameState state) =>
      List<String>.from(state.data['deck'] as List);

  List<String> _discardOf(GameState state) =>
      List<String>.from(state.data['discardPile'] as List);

  Map<String, int> _scoresOf(GameState state) {
    final raw = state.data['scores'] as Map;
    return raw.map((k, v) => MapEntry(k as String, v as int));
  }
}
