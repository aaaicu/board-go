import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import '../../../shared/game_pack/game_board_renderer.dart';
import '../../../shared/game_pack/views/board_view.dart';

/// Minimum zoom level (fully zoomed out).
const double _kMinZoom = 0.4;

/// Maximum zoom level (fully zoomed in).
const double _kMaxZoom = 3.0;

/// Default zoom applied when the game first loads.
const double _kDefaultZoom = 1.0;

/// A [FlameGame] that hosts a scrollable, pinch-zoomable game board world.
///
/// Responsibilities:
/// - Owns a [CameraComponent] pointed at the built-in [World].
/// - Handles pinch-to-zoom and drag-to-pan via [ScaleDetector].
/// - Delegates all visual content to a swappable [GameBoardRenderer].
///
/// Usage:
/// ```dart
/// final game = BoardWorldGame();
/// game.updateRenderer(MyPackRenderer());
///
/// // When a new server state arrives:
/// game.updateBoardView(boardView);
/// ```
class BoardWorldGame extends FlameGame with ScaleDetector {
  GameBoardRenderer? _renderer;

  /// Zoom level captured at the moment a scale gesture begins.
  double _startZoom = _kDefaultZoom;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera = CameraComponent(world: world);
    camera.viewfinder
      ..zoom = _kDefaultZoom
      ..anchor = Anchor.center;
  }

  @override
  void onRemove() {
    _renderer?.onDispose();
    super.onRemove();
  }

  // ---------------------------------------------------------------------------
  // Renderer management
  // ---------------------------------------------------------------------------

  /// Replaces the current renderer with [renderer].
  ///
  /// If a previous renderer was active it is disposed first. The new renderer's
  /// [GameBoardRenderer.onMount] is called immediately so it can populate the
  /// world with its initial components.
  void updateRenderer(GameBoardRenderer renderer) {
    _renderer?.onDispose();
    _renderer = renderer;
    renderer.onMount(this);
  }

  /// Forwards a new [BoardView] to the active renderer.
  ///
  /// No-op when no renderer has been set yet.
  void updateBoardView(BoardView boardView) {
    _renderer?.onBoardViewUpdate(boardView);
  }

  // ---------------------------------------------------------------------------
  // Gesture handling — pinch zoom + drag pan
  // ---------------------------------------------------------------------------

  @override
  void onScaleStart(ScaleStartInfo info) {
    _startZoom = camera.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    _applyZoom(info);
    _applyPan(info);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _applyZoom(ScaleUpdateInfo info) {
    final newZoom = (_startZoom * info.scale.global.length)
        .clamp(_kMinZoom, _kMaxZoom);
    camera.viewfinder.zoom = newZoom;
  }

  void _applyPan(ScaleUpdateInfo info) {
    // Divide delta by current zoom so the board moves at a consistent visual
    // speed regardless of zoom level.
    camera.viewfinder.position -=
        info.delta.global / camera.viewfinder.zoom;
  }
}
