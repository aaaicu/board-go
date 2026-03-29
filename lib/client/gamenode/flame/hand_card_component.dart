import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/painting.dart';

// ---------------------------------------------------------------------------
// Visual constants
// ---------------------------------------------------------------------------

/// Card width in world units.
const double kCardWidth = 80.0;

/// Card height in world units.
const double kCardHeight = 120.0;

/// Vertical offset applied to a selected card (moves up).
const double kCardSelectedLift = 12.0;

/// Corner radius of the card body.
const double kCardCornerRadius = 8.0;

// Company identity palette — matches stockpile_player_widget.dart and
// kCompanyColors in stock_price_tile_component.dart exactly.
const Map<String, Color> kNodeCompanyColors = {
  'aauto': Color(0xFFD44B3A),
  'epic': Color(0xFFE8A83C),
  'fed': Color(0xFF4A7BC8),
  'lehm': Color(0xFF9B6BBF),
  'sip': Color(0xFF7A7A7A),
  'tot': Color(0xFF4A9B6B),
};

const Map<String, String> kNodeCompanyShort = {
  'aauto': 'AAUTO',
  'epic': 'EPIC',
  'fed': 'FED',
  'lehm': 'LEHM',
  'sip': 'SIP',
  'tot': 'TOT',
};

// Background colours for fee / action cards.
const Color _kFeeBg = Color(0xFF4A4A4A);
const Color _kBoomBg = Color(0xFF3A9B5A); // green
const Color _kBustBg = Color(0xFFB83A3A); // red
const Color _kTextWhite = Color(0xFFFFFFFF);
const Color _kTextWhiteMuted = Color(0xCCFFFFFF);

// Selected glow colour (warm amber).
const Color _kSelectGlow = Color(0xFFFFBF40);

// ---------------------------------------------------------------------------
// HandCardComponent
// ---------------------------------------------------------------------------

/// A Flame component that renders one hand card and handles tap selection.
///
/// The card shifts [kCardSelectedLift] units upward when [isSelected] is true,
/// with a glowing amber border to indicate the selection.
///
/// [onTap] is called whenever the player taps this card. The parent game
/// decides whether to toggle selection or forward the event to Flutter.
class HandCardComponent extends PositionComponent with TapCallbacks {
  /// Card identifier (e.g. `'stock_aauto'`, `'fee_1000'`, `'action_boom'`).
  final String cardId;

  /// Index into the player's hand array — forwarded to the [onTap] callback.
  final int cardIndex;

  /// Whether this card is currently interactive (greyed out when false).
  final bool isInteractive;

  /// Callback invoked when the player taps this card.
  final void Function(int index) onTap;

  bool _selected = false;

  // Pre-allocated paints — reused every frame to avoid allocations.
  final Paint _bgPaint = Paint();
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8;
  final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..color = _kSelectGlow;
  final Paint _dimOverlayPaint = Paint()..color = const Color(0x66000000);

  Sprite? _logoSprite;

  HandCardComponent({
    required this.cardId,
    required this.cardIndex,
    required this.isInteractive,
    required this.onTap,
    required Vector2 position,
    Sprite? logoSprite,
  }) : super(
          size: Vector2(kCardWidth, kCardHeight),
          position: position,
          anchor: Anchor.bottomCenter,
        ) {
    _logoSprite = logoSprite;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  bool get isSelected => _selected;

  /// Toggles the selection state and adjusts the vertical lift.
  void setSelected(bool selected) {
    _selected = selected;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  // _logoSprite is injected via constructor by StockpileNodeGame (pre-cached).
  // No async image loading here — avoids Android path/cache issues.

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final liftY = _selected ? kCardSelectedLift : 0.0;
    canvas.save();
    canvas.translate(0, -liftY);

    if (cardId.startsWith('stock_')) {
      _renderStockCard(canvas);
    } else {
      _renderSpecialCard(canvas);
    }

    // Dim overlay when not interactive.
    if (!isInteractive) {
      final dimRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, kCardWidth, kCardHeight),
        const Radius.circular(kCardCornerRadius),
      );
      canvas.drawRRect(dimRRect, _dimOverlayPaint);
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Stock card rendering
  // ---------------------------------------------------------------------------

  void _renderStockCard(Canvas canvas) {
    final companyId = cardId.substring(6);
    final companyColor = kNodeCompanyColors[companyId] ?? const Color(0xFF888888);
    final short = kNodeCompanyShort[companyId] ?? companyId.toUpperCase();

    // Card body background — company colour at high alpha for visibility.
    final alpha = isInteractive ? (_selected ? 1.0 : 0.82) : 0.35;
    _bgPaint.color = companyColor.withValues(alpha: alpha);
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, kCardWidth, kCardHeight),
      const Radius.circular(kCardCornerRadius),
    );
    canvas.drawRRect(bodyRRect, _bgPaint);

    // Border.
    final borderAlpha = isInteractive ? (_selected ? 1.0 : 0.7) : 0.3;
    _borderPaint
      ..color = companyColor.withValues(alpha: borderAlpha)
      ..strokeWidth = _selected ? 2.5 : 1.8;
    canvas.drawRRect(bodyRRect, _borderPaint);

    // Selection glow — outer ring.
    if (_selected) {
      final glowRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-2, -2, kCardWidth + 4, kCardHeight + 4),
        const Radius.circular(kCardCornerRadius + 2),
      );
      canvas.drawRRect(glowRRect, _glowPaint);
    }

    // Company logo in the top 65% of the card.
    const logoAreaHeight = kCardHeight * 0.65;
    if (_logoSprite != null) {
      final clip = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, kCardWidth, logoAreaHeight),
        const Radius.circular(kCardCornerRadius),
      );
      canvas.save();
      canvas.clipRRect(clip);
      _logoSprite!.render(
        canvas,
        position: Vector2.zero(),
        size: Vector2(kCardWidth, logoAreaHeight),
      );
      canvas.restore();
    } else {
      // Monogram fallback — company-colour filled top area.
      final monoBg = Paint()..color = companyColor.withValues(alpha: 0.70);
      final monoRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, kCardWidth, logoAreaHeight),
        const Radius.circular(kCardCornerRadius),
      );
      canvas.drawRRect(monoRRect, monoBg);
      _drawCentredText(
        canvas,
        short[0],
        Rect.fromLTWH(0, 0, kCardWidth, logoAreaHeight),
        TextStyle(
          color: companyColor.withValues(alpha: isInteractive ? 0.8 : 0.4),
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // Ticker label in the bottom strip — white text on the now-dark background.
    _drawCentredText(
      canvas,
      short,
      Rect.fromLTWH(0, logoAreaHeight, kCardWidth, kCardHeight - logoAreaHeight),
      const TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Special card rendering (fee / action)
  // ---------------------------------------------------------------------------

  void _renderSpecialCard(Canvas canvas) {
    final Color bg;
    final String label;
    final String sublabel;

    switch (cardId) {
      case 'fee_1000':
        bg = _kFeeBg;
        label = '\$1K';
        sublabel = '수수료';
      case 'fee_2000':
        bg = _kFeeBg;
        label = '\$2K';
        sublabel = '수수료';
      case 'action_boom':
        bg = _kBoomBg;
        label = 'BOOM!';
        sublabel = '주가 상승';
      case 'action_bust':
        bg = _kBustBg;
        label = 'BUST!';
        sublabel = '주가 하락';
      default:
        bg = const Color(0xFF666655);
        label = cardId.length > 6 ? cardId.substring(0, 6) : cardId;
        sublabel = '';
    }

    final bgAlpha = isInteractive ? (_selected ? 1.0 : 0.85) : 0.4;
    _bgPaint.color = bg.withValues(alpha: bgAlpha);
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, kCardWidth, kCardHeight),
      const Radius.circular(kCardCornerRadius),
    );
    canvas.drawRRect(bodyRRect, _bgPaint);

    // Selection glow.
    if (_selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-2, -2, kCardWidth + 4, kCardHeight + 4),
          const Radius.circular(kCardCornerRadius + 2),
        ),
        _glowPaint,
      );
    }

    _drawCentredText(
      canvas,
      label,
      Rect.fromLTWH(0, kCardHeight * 0.3, kCardWidth, kCardHeight * 0.35),
      TextStyle(
        color: _kTextWhite.withValues(alpha: isInteractive ? 1.0 : 0.5),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );

    if (sublabel.isNotEmpty) {
      _drawCentredText(
        canvas,
        sublabel,
        Rect.fromLTWH(0, kCardHeight * 0.58, kCardWidth, kCardHeight * 0.2),
        TextStyle(
          color: _kTextWhiteMuted.withValues(alpha: isInteractive ? 1.0 : 0.4),
          fontSize: 10,
          fontWeight: FontWeight.normal,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Tap handling
  // ---------------------------------------------------------------------------

  @override
  void onTapUp(TapUpEvent event) {
    if (!isInteractive) return;
    onTap(cardIndex);
  }

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  void _drawCentredText(
    Canvas canvas,
    String text,
    Rect area,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: area.width);
    painter.paint(
      canvas,
      Offset(
        area.left + (area.width - painter.width) / 2,
        area.top + (area.height - painter.height) / 2,
      ),
    );
  }
}
