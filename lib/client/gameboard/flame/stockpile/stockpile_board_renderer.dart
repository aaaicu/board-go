import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../../../../shared/game_pack/game_board_renderer.dart';
import '../../../../shared/game_pack/views/board_view.dart';
import 'player_scoreboard_component.dart';
import 'stock_price_tile_component.dart';
import 'stockpile_pile_component.dart';
import 'table_background_component.dart';

// ---------------------------------------------------------------------------
// Layout constants (World coordinate space, origin = screen centre).
// ---------------------------------------------------------------------------

/// Vertical step between track rows (row height + padding).
const double _kRowStep = kTrackRowHeight + 7.0;

/// Total vertical span of the 6 track rows (6 companies).
const double _kTotalTrackHeight = _kRowStep * 6;

/// Y-centre of the topmost track row (world coords, origin = screen centre).
const double _kTrackTopCentreY = -_kTotalTrackHeight / 2 + kTrackRowHeight / 2;

/// Y position for the pile row (below the track section).
const double _kPilePrimaryY = _kTrackTopCentreY + _kTotalTrackHeight + 60.0;

/// Y centre of the player scoreboard (just above the track rows).
const double _kScoreboardCentreY = _kTrackTopCentreY - kTrackRowHeight / 2 - 28.0;

/// Horizontal span for distributing piles.
const double _kPileSpan = 700.0;

// ---------------------------------------------------------------------------
// StockpileBoardRenderer
// ---------------------------------------------------------------------------

/// [GameBoardRenderer] implementation for the Stockpile game pack.
///
/// Manages three layers of Flame components:
///   1. [TableBackgroundComponent] — cream/beige board background.
///   2. Six [StockTrackRowComponent]s — one per company, stacked vertically.
///   3. N [StockpilePileComponent]s — one per active pile, created /
///      destroyed as the pile list changes between rounds.
///
/// All coordinate maths targets World space where (0, 0) is the camera
/// anchor (screen centre).
class StockpileBoardRenderer implements GameBoardRenderer {
  /// Maps playerId → display name so bid badges can show a human-readable name.
  final Map<String, String> playerNames;

  late final World _world;

  // Component references for incremental updates.
  // Nullable because onMount is async — updateBoardView may fire before init.
  PlayerScoreboardComponent? _scoreboard;

  /// Cached board view received before [onMount] completed.
  /// Replayed at the end of [onMount] so the scoreboard shows from game start.
  BoardView? _pendingBoardView;

  // Track rows — indexed the same as kStockpileCompanies.
  final List<StockTrackRowComponent> _trackRows = [];
  final List<StockpilePileComponent> _piles = [];

  StockpileBoardRenderer({required this.playerNames});

  // ---------------------------------------------------------------------------
  // GameBoardRenderer
  // ---------------------------------------------------------------------------

  @override
  World get world => _world;

  @override
  Future<void> onMount(FlameGame game) async {
    // Reuse the game's built-in world so the camera already points at it.
    _world = game.world;

    // Background — always behind everything else.
    await _world.add(TableBackgroundComponent());

    // Player scoreboard — topmost strip.
    final scoreboard = PlayerScoreboardComponent(
      position: Vector2(0, _kScoreboardCentreY),
    );
    _scoreboard = scoreboard;
    await _world.add(scoreboard);

    // Build the six vertical-stacked track rows.
    await _buildTrackRows();

    // Replay any board view that arrived before init completed.
    if (_pendingBoardView != null) {
      onBoardViewUpdate(_pendingBoardView!);
      _pendingBoardView = null;
    }
  }

  @override
  void onBoardViewUpdate(BoardView boardView) {
    final data = boardView.data;

    // Guard: only process Stockpile pack updates.
    if (data['packId'] != 'stockpile') return;

    // onMount is async — buffer the view until init completes.
    if (_scoreboard == null) {
      _pendingBoardView = boardView;
      return;
    }

    _updateScoreboard(boardView);
    _updateStockPrices(data);
    _syncPiles(data);
  }

  @override
  void onDispose() {
    _world.removeAll(_world.children.toList());
  }

  // ---------------------------------------------------------------------------
  // Initialisation helpers
  // ---------------------------------------------------------------------------

  Future<void> _buildTrackRows() async {
    for (var i = 0; i < kStockpileCompanies.length; i++) {
      final row = StockTrackRowComponent(
        companyId: kStockpileCompanies[i],
        price: 0, // placeholder until first BoardView arrives
        position: _rowPosition(i),
      );
      _trackRows.add(row);
      await _world.add(row);
    }
  }

  // ---------------------------------------------------------------------------
  // Incremental update helpers
  // ---------------------------------------------------------------------------

  void _updateScoreboard(BoardView boardView) {
    _scoreboard?.setData(
      playerNames: playerNames,
      activeId: boardView.turnState?.activePlayerId,
    );
  }


  void _updateStockPrices(Map<String, dynamic> data) {
    final rawPrices = data['stockPrices'] as Map<String, dynamic>?;
    if (rawPrices == null) return;

    for (final row in _trackRows) {
      final price = rawPrices[row.companyId];
      if (price is int) {
        row.updatePrice(price);
      }
    }
  }

  void _syncPiles(Map<String, dynamic> data) {
    final rawPiles = data['stockpiles'] as List<dynamic>?;
    if (rawPiles == null) return;

    final pileCount = rawPiles.length;

    // Add missing pile components.
    while (_piles.length < pileCount) {
      final index = _piles.length;
      final pile = StockpilePileComponent(
        pileIndex: index,
        position: _pilePosition(index, pileCount),
      );
      _piles.add(pile);
      _world.add(pile);
    }

    // Remove excess pile components (e.g. between rounds).
    while (_piles.length > pileCount) {
      final removed = _piles.removeLast();
      _world.remove(removed);
    }

    // Reposition all piles in case count changed, then update data.
    for (var i = 0; i < _piles.length; i++) {
      _piles[i].position = _pilePosition(i, pileCount);
      _piles[i].refresh(
        rawPiles[i] as Map<String, dynamic>,
        playerNames,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Layout maths
  // ---------------------------------------------------------------------------

  /// Centre position (world coords) for company track row at [index].
  Vector2 _rowPosition(int index) {
    final y = _kTrackTopCentreY + index * _kRowStep;
    return Vector2(0, y);
  }

  /// Centre position (world coords) for pile [index] given [total] piles.
  Vector2 _pilePosition(int index, int total) {
    if (total <= 1) return Vector2(0, _kPilePrimaryY);
    final step = _kPileSpan / (total - 1);
    final x = -_kPileSpan / 2 + index * step;
    return Vector2(x, _kPilePrimaryY);
  }
}
