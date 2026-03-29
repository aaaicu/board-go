import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

import 'bid_button_component.dart';
import 'hand_card_component.dart';

// ---------------------------------------------------------------------------
// Layout constants (screen / world units)
// ---------------------------------------------------------------------------

/// Horizontal padding between cards.
const double _kCardGap = 10.0;

/// Vertical padding above the card row.
const double _kCardTopPad = 16.0;

/// Padding around the bid grid inside the game widget.
const double _kBidPad = 12.0;

// ---------------------------------------------------------------------------
// NodeGameMode
// ---------------------------------------------------------------------------

/// Controls which UI the game renders.
///
/// [handOnly] — supply phase: shows the card fan, no bid grid.
/// [bidOnly]  — demand phase: shows the bid grid, no card fan.
/// [handAndBid] — future mode if both are ever needed simultaneously.
enum NodeGameMode { handOnly, bidOnly, handAndBid }

// ---------------------------------------------------------------------------
// StockpileNodeGame
// ---------------------------------------------------------------------------

/// A lightweight [FlameGame] hosting interactive hand cards and / or a
/// calculator-style bid button grid for the GameNode phone UI.
///
/// Flutter → Flame communication: call [updateHand], [setSelectedCard],
/// [updateBidMode], or [setSelectedBid] to push new state in.
///
/// Flame → Flutter communication: register [onCardTap] and [onBidSelect]
/// callbacks before adding the game to the widget tree.
class StockpileNodeGame extends FlameGame with TapCallbacks {
  // ---------------------------------------------------------------------------
  // Flutter → Flame callbacks
  // ---------------------------------------------------------------------------

  /// Called when the player taps a hand card.
  /// Receives the card's index in the hand array.
  void Function(int index)? onCardTap;

  /// Called when the player taps a bid button.
  /// Receives the resolved total bid amount in dollars.
  void Function(int amount)? onBidSelect;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  NodeGameMode _mode = NodeGameMode.handOnly;

  /// True once the viewport has been laid out with a non-zero size.
  /// Guards against calling [size] before the GameWidget is measured.
  bool _hasBeenSized = false;

  List<String> _hand = const [];
  List<bool> _interactiveFlags = const [];
  int? _selectedCardIndex;

  int _bidBase = BidButtonGridComponent.kBaseBids.first;
  int _bidModifier = BidButtonGridComponent.kModifiers.first;

  final List<HandCardComponent> _cardComponents = [];
  BidButtonGridComponent? _bidGrid;

  /// Pre-loaded company logo sprites keyed by company id (e.g. 'aauto').
  final Map<String, Sprite> _companySprites = {};

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Color backgroundColor() => const Color(0x00000000); // fully transparent

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Assets live under assets/ (not assets/images/), so override Flame's default prefix.
    images.prefix = 'assets/';
    // Camera is fixed — no pan/zoom needed for the node phone UI.
    camera = CameraComponent(world: world);
    camera.viewfinder
      ..zoom = 1.0
      ..anchor = Anchor.topLeft;

    // Pre-load all company logos so HandCardComponent can receive them
    // synchronously — avoids Android async-load failures at card creation time.
    for (final entry in kNodeCompanyShort.entries) {
      final companyId = entry.key;
      final short = entry.value;
      try {
        final img = await images.load('gamepacks/stockpile/image/$short.png');
        _companySprites[companyId] = Sprite(img);
      } catch (_) {
        // Logo unavailable — HandCardComponent will fall back to monogram.
      }
    }

    // If updateHand() was called before sprites finished loading, rebuild so
    // cards get the correct logo rather than the monogram fallback.
    if (_hand.isNotEmpty) {
      _rebuildCards();
    }
  }

  /// Called by Flame when the GameWidget is first laid out (or resized).
  /// The first call with a non-zero size triggers an initial rebuild so that
  /// [_buildCardRow] / [_buildBidGrid] can safely read [size].
  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_hasBeenSized && size.x > 0) {
      _hasBeenSized = true;
      _rebuildAll();
    }
  }

  // ---------------------------------------------------------------------------
  // Public API — called from Flutter widget
  // ---------------------------------------------------------------------------

  /// Refreshes the displayed hand.
  ///
  /// [hand] is the ordered list of card IDs.
  /// [interactiveFlags] has the same length as [hand]; a `true` entry means
  /// the card at that index is tappable (has at least one allowed action).
  void updateHand(List<String> hand, List<bool> interactiveFlags) {
    _hand = hand;
    _interactiveFlags = interactiveFlags.length == hand.length
        ? interactiveFlags
        : List.filled(hand.length, true);
    _rebuildCards();
  }

  /// Marks the card at [index] as selected (or clears the selection when null).
  void setSelectedCard(int? index) {
    _selectedCardIndex = index;
    for (var i = 0; i < _cardComponents.length; i++) {
      _cardComponents[i].setSelected(i == index);
    }
  }

  /// Switches the game to [mode] and rebuilds the component tree.
  void updateMode(NodeGameMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _rebuildAll();
  }

  /// Updates the bid grid selection without firing [onBidSelect].
  void setSelectedBid({required int base, required int modifier}) {
    _bidBase = base;
    _bidModifier = modifier;
    _bidGrid?.setSelection(base: base, modifier: modifier);
  }

  // ---------------------------------------------------------------------------
  // Layout helpers
  // ---------------------------------------------------------------------------

  void _rebuildAll() {
    world.removeAll(world.children.toList());
    _cardComponents.clear();
    _bidGrid = null;

    switch (_mode) {
      case NodeGameMode.handOnly:
        _buildCardRow();
      case NodeGameMode.bidOnly:
        _buildBidGrid();
      case NodeGameMode.handAndBid:
        _buildCardRow();
        _buildBidGrid();
    }
  }

  void _rebuildCards() {
    // Remove only card components, leave bid grid intact.
    for (final c in _cardComponents) {
      world.remove(c);
    }
    _cardComponents.clear();
    _buildCardRow();
  }

  void _buildCardRow() {
    if (!_hasBeenSized || _hand.isEmpty || size.x == 0) return;

    final totalWidth =
        _hand.length * kCardWidth + (_hand.length - 1) * _kCardGap;
    final startX = (size.x - totalWidth) / 2;
    final cardBaseY = _kCardTopPad + kCardHeight;

    for (var i = 0; i < _hand.length; i++) {
      final interactive =
          i < _interactiveFlags.length ? _interactiveFlags[i] : true;
      Sprite? logoSprite;
      final cId = _hand[i].startsWith('stock_') ? _hand[i].substring(6) : null;
      if (cId != null) logoSprite = _companySprites[cId];

      final card = HandCardComponent(
        cardId: _hand[i],
        cardIndex: i,
        isInteractive: interactive,
        onTap: _handleCardTap,
        position: Vector2(
          startX + i * (kCardWidth + _kCardGap),
          cardBaseY,
        ),
        logoSprite: logoSprite,
      );
      if (i == _selectedCardIndex) card.setSelected(true);
      _cardComponents.add(card);
      world.add(card);
    }
  }

  void _buildBidGrid() {
    if (!_hasBeenSized || size.x == 0) return;
    final gridX = (size.x - kBidGridWidth) / 2;
    final gridY = _kBidPad;

    _bidGrid = BidButtonGridComponent(
      initialBase: _bidBase,
      initialModifier: _bidModifier,
      onBidSelect: _handleBidSelect,
      position: Vector2(gridX, gridY),
    );
    world.add(_bidGrid!);
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  void _handleCardTap(int index) {
    onCardTap?.call(index);
  }

  void _handleBidSelect(int amount) {
    onBidSelect?.call(amount);
  }
}
