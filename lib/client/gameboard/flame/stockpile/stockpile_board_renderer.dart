import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../../../../shared/game_pack/game_board_renderer.dart';
import '../../../../shared/game_pack/views/board_view.dart';
import 'stock_price_tile_component.dart';
import 'stockpile_pile_component.dart';
import 'table_background_component.dart';

// ---------------------------------------------------------------------------
// Layout constants (World coordinate space, origin = screen centre).
// ---------------------------------------------------------------------------

const double _kPriceTileY = -220.0;
const double _kPilePrimaryY = 60.0;

/// Horizontal span used when distributing tiles/piles evenly.
const double _kPriceTileSpan = 520.0;

/// Horizontal span for pile row.
const double _kPileSpan = 560.0;

// ---------------------------------------------------------------------------
// StockpileBoardRenderer
// ---------------------------------------------------------------------------

/// [GameBoardRenderer] implementation for the Stockpile game pack.
///
/// Manages three layers of Flame components:
///   1. [TableBackgroundComponent] — static dark wood background.
///   2. Six [StockPriceTileComponent]s — one per company, always present.
///   3. N [StockpilePileComponent]s — one per active pile, created /
///      destroyed as the pile list changes length between rounds.
///
/// All coordinate maths targets a World space where (0, 0) is the
/// camera anchor (screen centre).
class StockpileBoardRenderer implements GameBoardRenderer {
  /// Maps playerId → display name so bid badges can show a human-readable name.
  final Map<String, String> playerNames;

  late final World _world;

  // Component references for incremental updates.
  late final TableBackgroundComponent _background;
  final List<StockPriceTileComponent> _priceTiles = [];
  final List<StockpilePileComponent> _piles = [];

  StockpileBoardRenderer({required this.playerNames});

  // ---------------------------------------------------------------------------
  // GameBoardRenderer
  // ---------------------------------------------------------------------------

  @override
  World get world => _world;

  @override
  Future<void> onMount(FlameGame game) async {
    // Reuse the game's built-in world so the camera (set up in
    // BoardWorldGame.onLoad) already points at the same world.
    _world = game.world;

    // Background — lowest priority, always behind everything.
    _background = TableBackgroundComponent();
    await _world.add(_background);

    // Price tiles — six companies, distributed horizontally.
    await _buildPriceTiles();
  }

  @override
  void onBoardViewUpdate(BoardView boardView) {
    final data = boardView.data;

    // Guard: only process Stockpile pack updates.
    if (data['packId'] != 'stockpile') return;

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

  Future<void> _buildPriceTiles() async {
    const companies = kStockpileCompanies;
    final step = companies.isEmpty ? 0.0 : _kPriceTileSpan / (companies.length - 1);
    final startX = -_kPriceTileSpan / 2;

    for (var i = 0; i < companies.length; i++) {
      final tile = StockPriceTileComponent(
        companyId: companies[i],
        price: 0, // placeholder until first BoardView arrives
        position: Vector2(startX + i * step, _kPriceTileY),
      );
      _priceTiles.add(tile);
      await _world.add(tile);
    }
  }

  // ---------------------------------------------------------------------------
  // Incremental update helpers
  // ---------------------------------------------------------------------------

  void _updateStockPrices(Map<String, dynamic> data) {
    final rawPrices = data['stockPrices'] as Map<String, dynamic>?;
    if (rawPrices == null) return;

    for (final tile in _priceTiles) {
      final price = rawPrices[tile.companyId];
      if (price is int) {
        tile.updatePrice(price);
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

  /// Computes the world-space centre position for pile [index] given [total].
  Vector2 _pilePosition(int index, int total) {
    if (total <= 1) return Vector2(0, _kPilePrimaryY);
    final step = _kPileSpan / (total - 1);
    final x = -_kPileSpan / 2 + index * step;
    return Vector2(x, _kPilePrimaryY);
  }
}
