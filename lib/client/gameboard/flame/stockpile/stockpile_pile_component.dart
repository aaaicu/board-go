import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'stock_price_tile_component.dart'
    show kCompanyColors, kCompanyShort;

// ---------------------------------------------------------------------------
// Visual constants
// ---------------------------------------------------------------------------

const double _kPileWidth = 150.0;
const double _kPileHeight = 200.0;
const double _kCornerRadius = 10.0;

// Header zone (pile number + player count).
const double _kHeaderHeight = 36.0;

// Card preview zone.
const double _kCardAreaHeight = 86.0;

// Bid zone at the bottom.
const double _kBidAreaHeight = 52.0;

// Padding.
const double _kPad = 8.0;
const double _kInnerPad = 5.0;

// Card chip dimensions inside the preview area.
const double _kChipW = 40.0;
const double _kChipH = 26.0;
const double _kChipGap = 4.0;

// Face-down card chip dimensions.
const double _kFdW = 26.0;
const double _kFdH = 18.0;

// Background colours — cream/beige calculator style.
const Color _kBodyBg = Color(0xFFF0E8D0);
const Color _kHeaderBg = Color(0xFFE0D5B5);
const Color _kCardAreaBg = Color(0xFFE8DEBB);
const Color _kBidAreaBg = Color(0xFFD8CCAA);
const Color _kBorderColor = Color(0xFFBFAF88);
const Color _kTextDark = Color(0xFF3A3020);
const Color _kTextMuted = Color(0xFF8A7A55);
const Color _kFaceDownColor = Color(0xFF4A4030);
const Color _kFaceDownBorder = Color(0xFF7A6A50);
const Color _kBidHighlight = Color(0xFFE07820); // orange bid highlight
const Color _kNoBidColor = Color(0xFF9A8A65);

// ---------------------------------------------------------------------------
// StockpilePileComponent
// ---------------------------------------------------------------------------

/// Renders one physical Stockpile card pile (150 × 200 world units).
///
/// Visual style: cream/beige calculator aesthetic matching the original
/// board-game look.
///
/// Layout (top → bottom):
///   - Header: pile number + player-icon + count (36 px)
///   - Card preview: face-up chips + face-down stack (86 px)
///   - Bid area: current bid amount highlighted in orange (52 px)
///
/// Call [refresh] whenever the server broadcasts a new board state.
class StockpilePileComponent extends PositionComponent {
  final int pileIndex;

  List<String> _faceUpCards = const [];
  int _faceDownCount = 0;
  int? _currentBid;
  String? _currentBidderId;
  Map<String, String> _playerNames = const {};
  int _playerCount = 0;

  // Pre-allocated paints.
  final Paint _bodyPaint = Paint()..color = _kBodyBg;
  final Paint _headerPaint = Paint()..color = _kHeaderBg;
  final Paint _cardAreaPaint = Paint()..color = _kCardAreaBg;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = _kBorderColor;
  final Paint _innerBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8
    ..color = _kBorderColor;
  final Paint _shadowPaint = Paint()..color = const Color(0x33000000);
  final Paint _faceDownPaint = Paint()..color = _kFaceDownColor;
  final Paint _faceDownBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = _kFaceDownBorder;
  StockpilePileComponent({
    required this.pileIndex,
    required Vector2 position,
  }) : super(
          size: Vector2(_kPileWidth, _kPileHeight),
          position: position,
          anchor: Anchor.center,
        );

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Refreshes displayed data from a raw pile map.
  ///
  /// [pileData] keys:
  ///   `faceUpCards` (`List&lt;String&gt;`), `faceDownCount` (int),
  ///   `currentBid` (int?), `currentBidderId` (String?),
  ///   `playerCount` (int?).
  void refresh(Map<String, dynamic> pileData, Map<String, String> playerNames) {
    _faceUpCards =
        List<String>.from(pileData['faceUpCards'] as List? ?? const []);
    _faceDownCount = (pileData['faceDownCount'] as int?) ?? 0;
    _currentBid = pileData['currentBid'] as int?;
    _currentBidderId = pileData['currentBidderId'] as String?;
    _playerNames = playerNames;
    _playerCount = (pileData['playerCount'] as int?) ?? playerNames.length;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    // Drop shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, _kPileWidth, _kPileHeight),
        const Radius.circular(_kCornerRadius),
      ),
      _shadowPaint,
    );

    // Body.
    final bodyRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, _kPileWidth, _kPileHeight),
      const Radius.circular(_kCornerRadius),
    );
    canvas.drawRRect(bodyRRect, _bodyPaint);
    canvas.drawRRect(bodyRRect, _borderPaint);

    // Header zone.
    _drawHeader(canvas);

    // Card preview zone.
    _drawCardArea(canvas);

    // Bid area zone.
    _drawBidArea(canvas);
  }

  // ---------------------------------------------------------------------------
  // Zone drawing
  // ---------------------------------------------------------------------------

  void _drawHeader(Canvas canvas) {
    final headerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, _kPileWidth, _kHeaderHeight),
      const Radius.circular(_kCornerRadius),
    );
    canvas.drawRRect(headerRRect, _headerPaint);

    // Separator line below header.
    canvas.drawLine(
      Offset(0, _kHeaderHeight),
      Offset(_kPileWidth, _kHeaderHeight),
      _innerBorderPaint,
    );

    // Pile number label (left side).
    final pilePainter = TextPainter(
      text: TextSpan(
        text: '#${pileIndex + 1}',
        style: const TextStyle(
          color: _kTextDark,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pilePainter.paint(
      canvas,
      Offset(_kPad, (_kHeaderHeight - pilePainter.height) / 2),
    );

    // Player icon + count (right side).
    _drawPlayerBadge(canvas);
  }

  void _drawPlayerBadge(Canvas canvas) {
    // Person silhouette icon — simple circle + trapezoid.
    const iconRight = _kPileWidth - _kPad;
    final iconCx = iconRight - 22.0;
    final iconCy = _kHeaderHeight / 2;

    final iconPaint = Paint()..color = _kTextMuted;

    // Head.
    canvas.drawCircle(Offset(iconCx, iconCy - 5), 4, iconPaint);

    // Body (arc-ish trapezoid).
    final bodyPath = Path()
      ..moveTo(iconCx - 5, iconCy + 7)
      ..quadraticBezierTo(iconCx, iconCy + 1, iconCx + 5, iconCy + 7)
      ..close();
    canvas.drawPath(bodyPath, iconPaint);

    // Count number.
    final countPainter = TextPainter(
      text: TextSpan(
        text: '$_playerCount',
        style: const TextStyle(
          color: _kTextDark,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    countPainter.paint(
      canvas,
      Offset(
        iconRight - countPainter.width,
        (_kHeaderHeight - countPainter.height) / 2,
      ),
    );
  }

  void _drawCardArea(Canvas canvas) {
    const top = _kHeaderHeight;
    final cardAreaRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, _kPileWidth, _kCardAreaHeight),
      const Radius.circular(0),
    );
    canvas.drawRRect(cardAreaRRect, _cardAreaPaint);

    // Separator line below card area.
    canvas.drawLine(
      Offset(0, top + _kCardAreaHeight),
      Offset(_kPileWidth, top + _kCardAreaHeight),
      _innerBorderPaint,
    );

    // Face-up card chips.
    var x = _kPad;
    var y = top + _kInnerPad;
    final maxX = _kPileWidth - _kPad;
    final maxY = top + _kCardAreaHeight - _kFdH - _kInnerPad * 2;

    for (final cardId in _faceUpCards) {
      if (x + _kChipW > maxX) {
        x = _kPad;
        y += _kChipH + _kChipGap;
      }
      if (y + _kChipH > maxY) break; // clamp to face-up area

      _drawFaceUpChip(canvas, cardId, x, y);
      x += _kChipW + _kChipGap;
    }

    // Face-down stack at bottom of card area.
    if (_faceDownCount > 0) {
      final stackY = top + _kCardAreaHeight - _kFdH - _kInnerPad;
      _drawFaceDownStack(canvas, _kPad, stackY);
    }
  }

  void _drawBidArea(Canvas canvas) {
    final top = _kHeaderHeight + _kCardAreaHeight;
    final bidRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, _kPileWidth, _kBidAreaHeight),
      const Radius.circular(_kCornerRadius),
    );
    // Use a warm orange tint only when someone has actually bid (bidderId set).
    final hasBid = _currentBidderId != null;
    final bidBgColor = hasBid ? const Color(0xFFFFF3E8) : _kBidAreaBg;
    canvas.drawRRect(bidRRect, Paint()..color = bidBgColor);

    if (hasBid && _currentBid != null) {
      // Highlighted bid amount.
      final bidK = _currentBid! ~/ 1000;
      final bidLabel = '\$${bidK}K';

      final bidAmountPainter = TextPainter(
        text: TextSpan(
          text: bidLabel,
          style: const TextStyle(
            color: _kBidHighlight,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      bidAmountPainter.paint(
        canvas,
        Offset(
          (_kPileWidth - bidAmountPainter.width) / 2,
          top + _kInnerPad,
        ),
      );

      // Bidder name below.
      final bidderLabel = _bidderName();
      if (bidderLabel.isNotEmpty) {
        final bidderPainter = TextPainter(
          text: TextSpan(
            text: bidderLabel,
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: _kPileWidth - _kPad * 2);
        bidderPainter.paint(
          canvas,
          Offset(
            (_kPileWidth - bidderPainter.width) / 2,
            top + _kInnerPad + bidAmountPainter.height + 2,
          ),
        );
      }
    } else {
      // No bid yet.
      final noBidPainter = TextPainter(
        text: const TextSpan(
          text: '입찰 없음',
          style: TextStyle(
            color: _kNoBidColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      noBidPainter.paint(
        canvas,
        Offset(
          (_kPileWidth - noBidPainter.width) / 2,
          top + (_kBidAreaHeight - noBidPainter.height) / 2,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Card drawing helpers
  // ---------------------------------------------------------------------------

  void _drawFaceUpChip(Canvas canvas, String cardId, double x, double y) {
    final chipRect = Rect.fromLTWH(x, y, _kChipW, _kChipH);
    final chipRRect =
        RRect.fromRectAndRadius(chipRect, const Radius.circular(3));

    final chipColor = _chipColorForCard(cardId);
    canvas.drawRRect(chipRRect, Paint()..color = chipColor);
    canvas.drawRRect(
      chipRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = chipColor.withAlpha(200),
    );

    final label = _labelForCard(cardId);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        x + (_kChipW - tp.width) / 2,
        y + (_kChipH - tp.height) / 2,
      ),
    );
  }

  void _drawFaceDownStack(Canvas canvas, double x, double y) {
    final visibleCount = _faceDownCount.clamp(1, 5);
    for (var i = visibleCount - 1; i >= 0; i--) {
      final ox = x + i * 1.5;
      final oy = y - i * 1.5;
      final chipRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(ox, oy, _kFdW, _kFdH),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(chipRRect, _faceDownPaint);
      canvas.drawRRect(chipRRect, _faceDownBorderPaint);
    }

    // Count label next to the stack.
    if (_faceDownCount > 0) {
      final countPainter = TextPainter(
        text: TextSpan(
          text: '×$_faceDownCount',
          style: const TextStyle(
            color: _kTextMuted,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      countPainter.paint(
        canvas,
        Offset(
          x + _kFdW + 4,
          y + (_kFdH - countPainter.height) / 2,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Utility helpers
  // ---------------------------------------------------------------------------

  String _bidderName() {
    if (_currentBidderId == null) return '';
    return _playerNames[_currentBidderId!] ?? _currentBidderId!;
  }

  Color _chipColorForCard(String cardId) {
    if (cardId.startsWith('stock_')) {
      final companyId = cardId.substring(6);
      return kCompanyColors[companyId] ?? const Color(0xFF888888);
    }
    if (cardId.startsWith('fee_')) return const Color(0xFF666655);
    if (cardId == 'action_boom') return const Color(0xFF3A9B5A);
    if (cardId == 'action_bust') return const Color(0xFFB83A3A);
    return const Color(0xFF777766);
  }

  String _labelForCard(String cardId) {
    if (cardId.startsWith('stock_')) {
      final companyId = cardId.substring(6);
      return kCompanyShort[companyId] ?? companyId.toUpperCase();
    }
    if (cardId == 'fee_1000') return '\$1K';
    if (cardId == 'fee_2000') return '\$2K';
    if (cardId == 'action_boom') return 'BOOM';
    if (cardId == 'action_bust') return 'BUST';
    return cardId.length > 5 ? cardId.substring(0, 5) : cardId;
  }
}
