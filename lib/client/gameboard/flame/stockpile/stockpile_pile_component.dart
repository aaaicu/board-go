import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'stock_price_tile_component.dart'
    show kCompanyColors, kCompanyShort;

/// Visual constants for the pile layout.
const double _kPileWidth = 140.0;
const double _kPileHeight = 180.0;
const double _kCornerRadius = 10.0;
const double _kCardChipWidth = 36.0;
const double _kCardChipHeight = 22.0;
const double _kChipStackOffset = 4.0;
const double _kFaceDownWidth = 28.0;
const double _kFaceDownHeight = 20.0;
const double _kBadgeHeight = 28.0;

// ---------------------------------------------------------------------------
// StockpilePileComponent
// ---------------------------------------------------------------------------

/// Renders one physical Stockpile card pile (140 × 180 world units).
///
/// Layout (top → bottom):
///   - Pile number label
///   - Face-up cards as small colour chips (stacked with slight offset)
///   - Face-down cards as dark chip stack
///   - Bid badge (current bid amount + bidder name)
///
/// Call [update] whenever the server broadcasts a new board state.
class StockpilePileComponent extends PositionComponent {
  final int pileIndex;

  List<String> _faceUpCards = const [];
  int _faceDownCount = 0;
  int? _currentBid;
  String? _currentBidderId;
  Map<String, String> _playerNames = const {};

  // Pre-allocated paints.
  final Paint _containerPaint = Paint()
    ..color = const Color(0xFF2A1E12);
  final Paint _containerBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = const Color(0xFF5A3E2A);
  final Paint _shadowPaint = Paint()
    ..color = const Color(0x55000000);
  final Paint _faceDownPaint = Paint()
    ..color = const Color(0xFF1A1008);
  final Paint _faceDownBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0xFF5A3E2A);
  final Paint _badgePaint = Paint()
    ..color = const Color(0xFF3A2810);
  final Paint _badgeBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xFF8A6840);

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
  /// [pileData] keys: `faceUpCards` (List), `faceDownCount` (int),
  ///   `currentBid` (int?), `currentBidderId` (String?).
  /// [playerNames] maps playerId → display name.
  void refresh(Map<String, dynamic> pileData, Map<String, String> playerNames) {
    _faceUpCards =
        List<String>.from(pileData['faceUpCards'] as List? ?? const []);
    _faceDownCount = (pileData['faceDownCount'] as int?) ?? 0;
    _currentBid = pileData['currentBid'] as int?;
    _currentBidderId = pileData['currentBidderId'] as String?;
    _playerNames = playerNames;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final bounds = Rect.fromLTWH(0, 0, _kPileWidth, _kPileHeight);
    final rrect = RRect.fromRectAndRadius(
      bounds,
      const Radius.circular(_kCornerRadius),
    );

    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.translate(3, 3),
        const Radius.circular(_kCornerRadius),
      ),
      _shadowPaint,
    );

    // Container body + border.
    canvas.drawRRect(rrect, _containerPaint);
    canvas.drawRRect(rrect, _containerBorderPaint);

    // Pile number label.
    _drawPileLabel(canvas);

    // Card area.
    const cardAreaTop = 28.0;
    final cardAreaBottom = _kPileHeight - _kBadgeHeight - 8;
    _drawCards(canvas, cardAreaTop, cardAreaBottom);

    // Bid badge.
    _drawBidBadge(canvas);
  }

  // ---------------------------------------------------------------------------
  // Private drawing helpers
  // ---------------------------------------------------------------------------

  void _drawPileLabel(Canvas canvas) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Pile ${pileIndex + 1}',
        style: const TextStyle(
          color: Color(0xFFAA8866),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset((_kPileWidth - painter.width) / 2, 6));
  }

  void _drawCards(Canvas canvas, double top, double bottom) {
    const horizontalPadding = 10.0;

    // Lay out face-up cards in a single wrapped row with stacking offset.
    var x = horizontalPadding;
    var y = top + 4.0;

    for (final cardId in _faceUpCards) {
      if (x + _kCardChipWidth > _kPileWidth - horizontalPadding) {
        x = horizontalPadding;
        y += _kCardChipHeight + 2;
      }
      if (y + _kCardChipHeight > bottom) break; // clamp to area

      _drawFaceUpChip(canvas, cardId, x, y);
      x += _kCardChipWidth + _kChipStackOffset;
    }

    // Face-down cards — stack of dark chips at bottom-left of card area.
    if (_faceDownCount > 0) {
      final stackX = horizontalPadding;
      final stackY = bottom - _kFaceDownHeight - 2;
      _drawFaceDownStack(canvas, stackX, stackY);
    }
  }

  void _drawFaceUpChip(Canvas canvas, String cardId, double x, double y) {
    final chipRect = Rect.fromLTWH(x, y, _kCardChipWidth, _kCardChipHeight);
    final chipRRect = RRect.fromRectAndRadius(
      chipRect,
      const Radius.circular(4),
    );

    // Derive fill colour from cardId.
    final chipColor = _chipColorForCard(cardId);
    canvas.drawRRect(chipRRect, Paint()..color = chipColor);
    canvas.drawRRect(
      chipRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = chipColor.withAlpha(200),
    );

    // Abbreviated label.
    final label = _labelForCard(cardId);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 7,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        x + (_kCardChipWidth - tp.width) / 2,
        y + (_kCardChipHeight - tp.height) / 2,
      ),
    );
  }

  void _drawFaceDownStack(Canvas canvas, double x, double y) {
    final visibleCount = _faceDownCount.clamp(1, 4);
    for (var i = visibleCount - 1; i >= 0; i--) {
      final offsetX = x + i * 1.5;
      final offsetY = y - i * 1.5;
      final chipRect =
          Rect.fromLTWH(offsetX, offsetY, _kFaceDownWidth, _kFaceDownHeight);
      final chipRRect =
          RRect.fromRectAndRadius(chipRect, const Radius.circular(3));
      canvas.drawRRect(chipRRect, _faceDownPaint);
      canvas.drawRRect(chipRRect, _faceDownBorderPaint);
    }

    // Count badge.
    if (_faceDownCount > 0) {
      final countPainter = TextPainter(
        text: TextSpan(
          text: 'x$_faceDownCount',
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      countPainter.paint(
        canvas,
        Offset(
          x + _kFaceDownWidth + 3,
          y + (_kFaceDownHeight - countPainter.height) / 2,
        ),
      );
    }
  }

  void _drawBidBadge(Canvas canvas) {
    const badgeMargin = 6.0;
    final badgeRect = Rect.fromLTWH(
      badgeMargin,
      _kPileHeight - _kBadgeHeight - badgeMargin,
      _kPileWidth - badgeMargin * 2,
      _kBadgeHeight,
    );
    final badgeRRect =
        RRect.fromRectAndRadius(badgeRect, const Radius.circular(6));

    canvas.drawRRect(badgeRRect, _badgePaint);
    canvas.drawRRect(badgeRRect, _badgeBorderPaint);

    final bidText = _currentBid != null
        ? '\$${_currentBid! ~/ 1000}K  ${_bidderName()}'
        : 'No bid';
    final bidColor = _currentBid != null
        ? const Color(0xFFFFD700)
        : const Color(0xFF888888);

    final tp = TextPainter(
      text: TextSpan(
        text: bidText,
        style: TextStyle(
          color: bidColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: badgeRect.width - 8);
    tp.paint(
      canvas,
      Offset(
        badgeRect.left + (badgeRect.width - tp.width) / 2,
        badgeRect.top + (badgeRect.height - tp.height) / 2,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Utility helpers
  // ---------------------------------------------------------------------------

  String _bidderName() {
    if (_currentBidderId == null) return '';
    return _playerNames[_currentBidderId!] ?? _currentBidderId!;
  }

  /// Returns a chip fill colour derived from the card ID.
  Color _chipColorForCard(String cardId) {
    if (cardId.startsWith('stock_')) {
      final companyId = cardId.substring(6);
      return kCompanyColors[companyId] ?? const Color(0xFF888888);
    }
    if (cardId.startsWith('fee_')) return const Color(0xFF555555);
    if (cardId == 'action_boom') return const Color(0xFF4CAF50);
    if (cardId == 'action_bust') return const Color(0xFFE05252);
    return const Color(0xFF666666);
  }

  /// Returns a short display label for the card chip.
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
