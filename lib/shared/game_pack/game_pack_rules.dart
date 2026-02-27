import '../game_session/game_session_state.dart';
import 'player_action.dart';
import 'views/allowed_action.dart';
import 'views/board_view.dart';
import 'views/player_view.dart';

/// Strategy interface that encapsulates all rules for a specific game pack.
///
/// Each game pack provides one implementation of this interface.  The
/// [GameServer] delegates all game-logic decisions here, keeping the server
/// itself free of game-specific knowledge.
///
/// All methods are pure functions — they must not hold mutable state, and
/// must not produce side effects.  The sole source of truth is the
/// [GameSessionState] passed into each call.
abstract class GamePackRules {
  /// Stable, unique identifier for this pack (e.g. 'simple_card_game').
  String get packId;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Creates the initial [GameSessionState] for a new game.
  ///
  /// Receives the lobby-phase [sessionState] (players already populated)
  /// and must return a new state with:
  ///   - [SessionPhase.inGame] phase
  ///   - game data initialised in [GameSessionState.gameState]
  ///   - [TurnState] initialised with round 1, turnIndex 0
  ///
  /// Must be a pure function — [sessionState] must not be mutated.
  GameSessionState createInitialGameState(GameSessionState sessionState);

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns the list of actions [playerId] is currently permitted to take.
  ///
  /// Returns an empty list when it is not [playerId]'s turn, or when the
  /// game has ended.
  List<AllowedAction> getAllowedActions(
    GameSessionState state,
    String playerId,
  );

  // ---------------------------------------------------------------------------
  // Mutation (pure)
  // ---------------------------------------------------------------------------

  /// Applies [action] to [state] and returns the resulting [GameSessionState].
  ///
  /// Must be a pure function — [state] must not be mutated.
  /// The caller is responsible for validating that [action] is in the allowed
  /// list before calling this method.
  GameSessionState applyAction(
    GameSessionState state,
    String playerId,
    PlayerAction action,
  );

  // ---------------------------------------------------------------------------
  // End condition
  // ---------------------------------------------------------------------------

  /// Checks whether the game has ended in [state].
  ///
  /// Returns a record with:
  ///   - [ended]: true if the game is over.
  ///   - [winnerIds]: the player IDs who won (may be empty on a draw).
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState state);

  // ---------------------------------------------------------------------------
  // View builders
  // ---------------------------------------------------------------------------

  /// Builds the public board view sent to the GameBoard (iPad) after every
  /// action.  Must never include any player's private hand.
  BoardView buildBoardView(GameSessionState state);

  /// Builds the private view sent exclusively to [playerId]'s device.
  ///
  /// Security invariant: the returned [PlayerView.hand] must contain ONLY the
  /// cards belonging to [playerId].  No other player's hand may be included.
  PlayerView buildPlayerView(GameSessionState state, String playerId);
}
