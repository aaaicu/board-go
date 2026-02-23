import 'game_state.dart';
import 'player_action.dart';

/// Contract that every game pack must fulfill.
///
/// The [GameServer] calls these methods to drive game logic while remaining
/// fully decoupled from any specific game's rules.
abstract class GamePackInterface {
  /// Called once when the server starts a new game session.
  Future<void> initialize(GameState initialState);

  /// Validates whether [action] is legal in [currentState].
  ///
  /// Return `true` if the action should be processed, `false` to reject it.
  bool validateAction(PlayerAction action, GameState currentState);

  /// Applies [action] to [currentState] and returns the resulting [GameState].
  ///
  /// This method must be pure — it must not mutate [currentState].
  GameState processAction(PlayerAction action, GameState currentState);

  /// Called when the game session ends or the server shuts down.
  Future<void> dispose();
}
