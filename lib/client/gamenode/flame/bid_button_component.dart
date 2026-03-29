import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';

// ---------------------------------------------------------------------------
// Visual constants — cream/beige calculator aesthetic matching the board
// ---------------------------------------------------------------------------

const double _kButtonWidth = 70.0;
const double _kButtonHeight = 48.0;
const double _kButtonGap = 8.0;
const double _kCornerRadius = 10.0;

/// Height of the total-amount label row above the button grid.
const double _kTotalLabelHeight = 36.0;

/// Vertical gap between the total label and the button grid.
const double _kTotalLabelGap = 10.0;

/// Total width of the 4-button grid row.
const double kBidGridWidth = _kButtonWidth * 4 + _kButtonGap * 3;

/// Total height of the component: total-amount label + gap + 2-row grid.
const double kBidGridHeight =
    _kTotalLabelHeight + _kTotalLabelGap + _kButtonHeight * 2 + _kButtonGap;

// Cream / beige background — matching the board's pile aesthetic.
const Color _kButtonBg = Color(0xFFF0E8D0);
const Color _kButtonBorder = Color(0xFFBFAF88);
const Color _kTextDark = Color(0xFF3A3020);

/// Orange highlight colour for the currently selected button (matches the
/// board's bid highlight and the spec exactly).
const Color _kHighlight = Color(0xFFE8A040);
const Color _kHighlightText = Color(0xFFFFFFFF);

// ---------------------------------------------------------------------------
// BidButtonGroup — an individual button cell in the grid
// ---------------------------------------------------------------------------

/// One rectangular bid button.
///
/// [isSelected] renders the button with the orange highlight background.
/// [onTap] fires with [value] when the player taps this button.
class _BidButtonCell extends PositionComponent with TapCallbacks {
  final String label;
  final int value;
  final bool isSelected;
  final void Function(int value) onTap;

  final Paint _bgPaint = Paint();
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  _BidButtonCell({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
    required Vector2 position,
  }) : super(
          size: Vector2(_kButtonWidth, _kButtonHeight),
          position: position,
          anchor: Anchor.topLeft,
        );

  @override
  void render(Canvas canvas) {
    final bg = isSelected ? _kHighlight : _kButtonBg;
    _bgPaint.color = bg;
    _borderPaint.color = isSelected
        ? _kHighlight.withValues(alpha: 0.6)
        : _kButtonBorder;

    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, _kButtonWidth, _kButtonHeight),
      const Radius.circular(_kCornerRadius),
    );
    canvas.drawRRect(rRect, _bgPaint);
    canvas.drawRRect(rRect, _borderPaint);

    final textColor = isSelected ? _kHighlightText : _kTextDark;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _kButtonWidth);
    painter.paint(
      canvas,
      Offset(
        (_kButtonWidth - painter.width) / 2,
        (_kButtonHeight - painter.height) / 2,
      ),
    );
  }

  @override
  void onTapUp(TapUpEvent event) => onTap(value);
}

// ---------------------------------------------------------------------------
// BidButtonGridComponent
// ---------------------------------------------------------------------------

/// A 4×2 calculator-style bid button grid rendered entirely in Flame.
///
/// Row 0 (base bid):  10K | 15K | 20K | 25K
/// Row 1 (modifier):  +0  | +1K | +3K | +6K
///
/// The currently selected base and modifier are highlighted in orange.
/// [onBidSelect] is fired whenever a button is tapped, passing the
/// resolved total bid amount (base + modifier) in dollars.
class BidButtonGridComponent extends PositionComponent {
  /// The four fixed base-bid amounts (in dollars).
  static const List<int> kBaseBids = [10000, 15000, 20000, 25000];

  /// The four modifier amounts (in dollars).
  static const List<int> kModifiers = [0, 1000, 3000, 6000];

  static const List<String> _baseLabels = ['10K', '15K', '20K', '25K'];
  static const List<String> _modLabels = ['+0', '+1K', '+3K', '+6K'];

  int _selectedBase;
  int _selectedModifier;

  /// Called whenever the player selects a button.
  /// Receives the resolved total amount (base + modifier) in dollars.
  final void Function(int amount) onBidSelect;

  BidButtonGridComponent({
    required int initialBase,
    required int initialModifier,
    required this.onBidSelect,
    required Vector2 position,
  })  : _selectedBase = initialBase,
        _selectedModifier = initialModifier,
        super(
          size: Vector2(kBidGridWidth, kBidGridHeight),
          position: position,
          anchor: Anchor.topLeft,
        );

  // ---------------------------------------------------------------------------
  // Rendering — total amount label above the button grid
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _drawTotalLabel(canvas);
  }

  void _drawTotalLabel(Canvas canvas) {
    final total = _selectedBase + _selectedModifier;
    final hasSelection = total > 0;

    if (hasSelection) {
      final bidK = total ~/ 1000;
      final label = '\$${bidK}K';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: _kHighlight,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: kBidGridWidth);
      painter.paint(
        canvas,
        Offset(
          (kBidGridWidth - painter.width) / 2,
          (_kTotalLabelHeight - painter.height) / 2,
        ),
      );
    } else {
      final painter = TextPainter(
        text: const TextSpan(
          text: '입찰 금액 선택',
          style: TextStyle(
            color: Color(0xFFAA9977),
            fontSize: 15,
            fontWeight: FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: kBidGridWidth);
      painter.paint(
        canvas,
        Offset(
          (kBidGridWidth - painter.width) / 2,
          (_kTotalLabelHeight - painter.height) / 2,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _rebuildButtons();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the current total bid amount (selected base + selected modifier).
  int get currentAmount => _selectedBase + _selectedModifier;

  /// Updates which base / modifier is highlighted without triggering the
  /// callback. Used to sync state after a server update.
  void setSelection({required int base, required int modifier}) {
    _selectedBase = base;
    _selectedModifier = modifier;
    _rebuildButtons();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _rebuildButtons() {
    removeAll(children.toList());

    // Vertical offset — push grid below the total-amount label.
    const gridOffsetY = _kTotalLabelHeight + _kTotalLabelGap;

    // Row 0 — base bid.
    for (var i = 0; i < kBaseBids.length; i++) {
      final base = kBaseBids[i];
      add(_BidButtonCell(
        label: _baseLabels[i],
        value: base,
        isSelected: base == _selectedBase,
        onTap: _onBaseTapped,
        position: Vector2(i * (_kButtonWidth + _kButtonGap), gridOffsetY),
      ));
    }

    // Row 1 — modifier.
    for (var i = 0; i < kModifiers.length; i++) {
      final mod = kModifiers[i];
      add(_BidButtonCell(
        label: _modLabels[i],
        value: mod,
        isSelected: mod == _selectedModifier,
        onTap: _onModifierTapped,
        position: Vector2(
          i * (_kButtonWidth + _kButtonGap),
          gridOffsetY + _kButtonHeight + _kButtonGap,
        ),
      ));
    }
  }

  void _onBaseTapped(int base) {
    _selectedBase = base;
    _rebuildButtons();
    onBidSelect(_selectedBase + _selectedModifier);
  }

  void _onModifierTapped(int modifier) {
    _selectedModifier = modifier;
    _rebuildButtons();
    onBidSelect(_selectedBase + _selectedModifier);
  }
}
