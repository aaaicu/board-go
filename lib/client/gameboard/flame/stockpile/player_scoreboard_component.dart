import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------

const double _kCardW = 110.0;
const double _kCardH = 44.0;
const double _kCardGap = 10.0;
const double _kCornerRadius = 8.0;
const double _kPad = 8.0;

// Colours
const Color _kCardBg = Color(0xFFF0E8D0);
const Color _kCardBorder = Color(0xFFBFAF88);
const Color _kActiveBorder = Color(0xFFE8A040); // amber — active player
const Color _kActiveGlow = Color(0x33E8A040);
const Color _kTextDark = Color(0xFF3A3020);
const Color _kActiveBg = Color(0xFFFFF8EC);

// ---------------------------------------------------------------------------
// PlayerScoreboardComponent
// ---------------------------------------------------------------------------

/// Horizontal strip of player-status cards shown at the top of the board.
///
/// Each card shows the player's display name and cash balance.
/// The active player's card is highlighted with an amber border and warm bg.
///
/// Call [setData] whenever the board state changes.
class PlayerScoreboardComponent extends PositionComponent {
  // Ordered list of [playerId, displayName, cash, isActive].
  final List<_PlayerCard> _cards = [];

  // Pre-allocated paints.
  final Paint _activeBgPaint = Paint()..color = _kActiveBg;
  final Paint _cardBgPaint = Paint()..color = _kCardBg;
  final Paint _activeBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = _kActiveBorder;
  final Paint _cardBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = _kCardBorder;
  final Paint _activeGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5.0
    ..color = _kActiveGlow;

  PlayerScoreboardComponent({required Vector2 position})
      : super(
          // Width/height computed once data arrives.
          size: Vector2(0, _kCardH),
          position: position,
          anchor: Anchor.center,
        );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Updates displayed data.
  ///
  /// [playerNames] — playerId → display name.
  /// [activeId]    — playerId of the player whose turn it currently is.
  void setData({
    required Map<String, String> playerNames,
    required String? activeId,
  }) {
    _cards.clear();

    for (final entry in playerNames.entries) {
      _cards.add(_PlayerCard(
        name: entry.value,
        isActive: entry.key == activeId,
      ));
    }

    // Resize component to fit all cards.
    final totalW =
        _cards.length * _kCardW + (_cards.length - 1).clamp(0, 99) * _kCardGap;
    size = Vector2(totalW, _kCardH);
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    if (_cards.isEmpty) return;

    for (var i = 0; i < _cards.length; i++) {
      final x = i * (_kCardW + _kCardGap);
      _drawCard(canvas, _cards[i], x);
    }
  }

  void _drawCard(Canvas canvas, _PlayerCard card, double x) {
    final rect = Rect.fromLTWH(x, 0, _kCardW, _kCardH);
    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(_kCornerRadius));

    // Background.
    canvas.drawRRect(rRect, card.isActive ? _activeBgPaint : _cardBgPaint);

    // Glow + border.
    if (card.isActive) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 3, -3, _kCardW + 6, _kCardH + 6),
          const Radius.circular(_kCornerRadius + 3),
        ),
        _activeGlowPaint,
      );
      canvas.drawRRect(rRect, _activeBorderPaint);
    } else {
      canvas.drawRRect(rRect, _cardBorderPaint);
    }

    // Active indicator dot (top-right corner).
    if (card.isActive) {
      canvas.drawCircle(
        Offset(x + _kCardW - _kPad - 4, _kCardH / 2),
        5,
        Paint()..color = _kActiveBorder,
      );
    }

    // Player name — centred vertically in the card.
    final namePainter = TextPainter(
      text: TextSpan(
        text: card.name,
        style: TextStyle(
          color: card.isActive ? _kActiveBorder : _kTextDark,
          fontSize: 14,
          fontWeight: card.isActive ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: _kCardW - _kPad * 2 - 14);
    namePainter.paint(
      canvas,
      Offset(
        x + _kPad,
        (_kCardH - namePainter.height) / 2,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal data holder
// ---------------------------------------------------------------------------

class _PlayerCard {
  final String name;
  final bool isActive;

  const _PlayerCard({required this.name, required this.isActive});
}
