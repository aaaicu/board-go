import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'views/board_view.dart';

// Forward reference — BoardWorldGame is defined in
// lib/client/gameboard/flame/board_world_game.dart.
// Import that file in concrete renderer implementations.

/// Abstract contract for game-pack–specific Flame board renderers.
///
/// Each game pack provides its own [GameBoardRenderer] implementation that
/// knows how to translate a [BoardView] into Flame components (tiles, tokens,
/// stockpiles, etc.).
///
/// Lifecycle:
///   1. [onMount] — called once when the renderer is added to the game world.
///      Add your initial components here.
///   2. [onBoardViewUpdate] — called every time the server broadcasts a new
///      [BoardView]. Update / replace components to reflect the new state.
///   3. [onDispose] — called when the game is torn down.
abstract class GameBoardRenderer {
  /// The Flame [World] this renderer populates.
  World get world;

  /// Called once when the renderer is mounted into its host [FlameGame].
  ///
  /// The [game] parameter is typed as [FlameGame] to avoid a circular import
  /// between this shared interface and the client-layer [BoardWorldGame].
  /// Concrete renderers may downcast to [BoardWorldGame] when needed.
  Future<void> onMount(FlameGame game);

  /// Called every time a new [BoardView] arrives from the server.
  void onBoardViewUpdate(BoardView boardView);

  /// Called when the game session ends or the widget is disposed.
  void onDispose();
}
