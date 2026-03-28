import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

// ---------------------------------------------------------------------------
// Constants shared across Stockpile Flame components.
// ---------------------------------------------------------------------------

const List<String> kStockpileCompanies = [
  'aauto',
  'epic',
  'fed',
  'lehm',
  'sip',
  'tot',
];

/// Original board-game palette — one distinct hue per company.
const Map<String, Color> kCompanyColors = {
  'aauto': Color(0xFFD44B3A), // red   — American Automotive
  'epic': Color(0xFFE8A83C), // amber — Epic Electric
  'fed': Color(0xFF4A7BC8), // blue  — Cosmic Computers
  'lehm': Color(0xFF9B6BBF), // purple — Leading Laboratories
  'sip': Color(0xFF7A7A7A), // grey  — Stanford Steel
  'tot': Color(0xFF4A9B6B), // green — Bottomline Bank
};

const Map<String, String> kCompanyShort = {
  'aauto': 'AAUTO',
  'epic': 'EPIC',
  'fed': 'FED',
  'lehm': 'LEHM',
  'sip': 'SIP',
  'tot': 'TOT',
};

const Map<String, String> kCompanyName = {
  'aauto': 'American Automotive',
  'epic': 'Epic Electric',
  'fed': 'Cosmic Computers',
  'lehm': 'Leading Labs',
  'sip': 'Stanford Steel',
  'tot': 'Bottomline Bank',
};

/// Returns the sprite asset path for a company logo.
String companyImagePath(String companyId) =>
    'gamepacks/stockpile/image/${companyShort(companyId)}.png';

/// Returns the short ticker symbol for a company.
String companyShort(String companyId) =>
    kCompanyShort[companyId] ?? companyId.toUpperCase();

// ---------------------------------------------------------------------------
// Layout constants
// ---------------------------------------------------------------------------

/// Total width of one track row in world units.
const double kTrackRowWidth = 900.0;

/// Height of one track row in world units.
const double kTrackRowHeight = 68.0;

/// Number of price steps on the track.
const int kPriceSteps = 10;

/// Width of the trash-icon column on the far left.
const double _kTrashWidth = 36.0;

/// Width of the company logo + name panel.
const double _kLogoWidth = 130.0;

/// Width of the dividend-icon column on the far right.
const double _kDividendWidth = 40.0;

/// Horizontal padding between sections.
const double _kSectionGap = 6.0;

// ---------------------------------------------------------------------------
// StockTrackRowComponent
// (file kept as stock_price_tile_component.dart to minimise import churn)
// ---------------------------------------------------------------------------

/// A horizontal price-track row for one company (kTrackRowWidth × kTrackRowHeight).
///
/// Layout (left → right):
///   [trash icon] [company logo+name] [1][2]…[10] [$ icon]
///
/// The current price position is highlighted as a filled circle in the
/// company colour with the price number in white bold text.
class StockTrackRowComponent extends PositionComponent {
  final String companyId;
  int price;

  Sprite? _logoSprite;

  // Pre-allocated paints — reused every frame.
  final Paint _rowBgPaint = Paint();
  final Paint _logoBgPaint = Paint();
  final Paint _stepBgPaint = Paint();
  final Paint _markerPaint = Paint();
  final Paint _dividerPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x22000000);
  final Paint _shadowPaint = Paint()..color = const Color(0x22000000);

  StockTrackRowComponent({
    required this.companyId,
    required this.price,
    required Vector2 position,
  }) : super(
          size: Vector2(kTrackRowWidth, kTrackRowHeight),
          position: position,
          anchor: Anchor.center,
        );

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _logoSprite = await Sprite.load(companyImagePath(companyId));
    } catch (_) {
      // Logo unavailable — fallback monogram rendered in render().
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void updatePrice(int newPrice) {
    price = newPrice;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final companyColor = kCompanyColors[companyId] ?? const Color(0xFF888888);

    // ------------------------------------------------------------------
    // Row background — very light tint of company colour, rounded rect.
    // ------------------------------------------------------------------
    final rowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, kTrackRowWidth, kTrackRowHeight),
      const Radius.circular(6),
    );
    _rowBgPaint.color = const Color(0xFFF5EFE0); // cream base
    canvas.drawRRect(rowRect, _rowBgPaint);

    // Subtle bottom shadow line separating rows.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, kTrackRowHeight - 2, kTrackRowWidth, 2),
        const Radius.circular(2),
      ),
      _shadowPaint,
    );

    // ------------------------------------------------------------------
    // Trash icon column (left).
    // ------------------------------------------------------------------
    _drawTrashIcon(canvas, companyColor);

    // ------------------------------------------------------------------
    // Company logo + name panel.
    // ------------------------------------------------------------------
    final logoPanelLeft = _kTrashWidth + _kSectionGap;
    _drawLogoPanel(canvas, logoPanelLeft, companyColor);

    // ------------------------------------------------------------------
    // Price track cells [1..10].
    // ------------------------------------------------------------------
    final trackLeft = logoPanelLeft + _kLogoWidth + _kSectionGap;
    final trackRight = kTrackRowWidth - _kDividendWidth - _kSectionGap;
    final trackWidth = trackRight - trackLeft;
    final cellWidth = trackWidth / kPriceSteps;

    _drawPriceTrack(canvas, trackLeft, cellWidth, companyColor);

    // ------------------------------------------------------------------
    // Dividend / $ icon column (right).
    // ------------------------------------------------------------------
    _drawDividendIcon(canvas, kTrackRowWidth - _kDividendWidth, companyColor);
  }

  // ---------------------------------------------------------------------------
  // Section drawing helpers
  // ---------------------------------------------------------------------------

  void _drawTrashIcon(Canvas canvas, Color companyColor) {
    // Circular background.
    final cx = _kTrashWidth / 2;
    final cy = kTrackRowHeight / 2;
    final iconPaint = Paint()..color = companyColor.withValues(alpha: 0.15);
    canvas.drawCircle(Offset(cx, cy), 14, iconPaint);

    // Trash bin drawn with canvas primitives.
    final binPaint = Paint()
      ..color = companyColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Lid.
    canvas.drawLine(Offset(cx - 7, cy - 5), Offset(cx + 7, cy - 5), binPaint);
    // Handle on lid.
    canvas.drawLine(Offset(cx - 3, cy - 5), Offset(cx - 3, cy - 7), binPaint);
    canvas.drawLine(Offset(cx + 3, cy - 5), Offset(cx + 3, cy - 7), binPaint);
    canvas.drawLine(Offset(cx - 3, cy - 7), Offset(cx + 3, cy - 7), binPaint);
    // Body.
    final bodyRect = Rect.fromLTWH(cx - 5.5, cy - 4.5, 11, 11);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(1.5)),
      binPaint,
    );
    // Vertical lines inside body.
    canvas.drawLine(Offset(cx - 2, cy - 2), Offset(cx - 2, cy + 5), binPaint);
    canvas.drawLine(Offset(cx + 2, cy - 2), Offset(cx + 2, cy + 5), binPaint);
  }

  void _drawLogoPanel(Canvas canvas, double left, Color companyColor) {
    const vertPad = 5.0;
    const horzPad = 6.0;
    final panelRect = Rect.fromLTWH(
      left,
      vertPad,
      _kLogoWidth,
      kTrackRowHeight - vertPad * 2,
    );
    final panelRRect =
        RRect.fromRectAndRadius(panelRect, const Radius.circular(5));

    // Company-colour filled background.
    _logoBgPaint.color = companyColor;
    canvas.drawRRect(panelRRect, _logoBgPaint);

    // Logo sprite (if loaded) in the left portion of the panel.
    final logoAreaWidth = _kLogoWidth * 0.45;
    if (_logoSprite != null) {
      _logoSprite!.render(
        canvas,
        position: Vector2(left + horzPad, vertPad + 2),
        size: Vector2(logoAreaWidth - horzPad, kTrackRowHeight - vertPad * 2 - 4),
      );
    } else {
      _drawMonogram(canvas, left + horzPad, vertPad, logoAreaWidth);
    }

    // Ticker and company name text on the right side of the panel.
    final textLeft = left + logoAreaWidth + horzPad;
    final availWidth = _kLogoWidth - logoAreaWidth - horzPad * 2;

    final tickerPainter = TextPainter(
      text: TextSpan(
        text: kCompanyShort[companyId] ?? companyId.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: availWidth);
    tickerPainter.paint(
      canvas,
      Offset(textLeft, kTrackRowHeight / 2 - tickerPainter.height - 1),
    );

    final namePainter = TextPainter(
      text: TextSpan(
        text: kCompanyName[companyId] ?? companyId,
        style: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 9,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: availWidth);
    namePainter.paint(
      canvas,
      Offset(textLeft, kTrackRowHeight / 2 + 2),
    );
  }

  void _drawPriceTrack(
    Canvas canvas,
    double trackLeft,
    double cellWidth,
    Color companyColor,
  ) {
    const vertPad = 5.0;
    const cellPad = 2.0;
    final cellHeight = kTrackRowHeight - vertPad * 2;

    for (var i = 1; i <= kPriceSteps; i++) {
      final cellLeft = trackLeft + (i - 1) * cellWidth;
      final cellRect = Rect.fromLTWH(
        cellLeft + cellPad,
        vertPad,
        cellWidth - cellPad * 2,
        cellHeight,
      );
      final cellRRect =
          RRect.fromRectAndRadius(cellRect, const Radius.circular(4));

      final isCurrentPrice = i == price;

      if (isCurrentPrice) {
        // Filled company-colour circle as marker.
        final cx = cellRect.center.dx;
        final cy = cellRect.center.dy;
        final markerRadius = (cellHeight * 0.42).clamp(12.0, 24.0);
        _markerPaint.color = companyColor;
        canvas.drawCircle(Offset(cx, cy), markerRadius, _markerPaint);

        // Price number in white bold.
        final numPainter = TextPainter(
          text: TextSpan(
            text: '$i',
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        numPainter.paint(
          canvas,
          Offset(cx - numPainter.width / 2, cy - numPainter.height / 2),
        );
      } else {
        // Subtle company-colour tinted cell background.
        _stepBgPaint.color = companyColor.withValues(alpha: 0.12);
        canvas.drawRRect(cellRRect, _stepBgPaint);

        // Cell number in company colour (dimmed).
        final numPainter = TextPainter(
          text: TextSpan(
            text: '$i',
            style: TextStyle(
              color: companyColor.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        numPainter.paint(
          canvas,
          Offset(
            cellRect.center.dx - numPainter.width / 2,
            cellRect.center.dy - numPainter.height / 2,
          ),
        );

        // Right-edge divider between cells.
        if (i < kPriceSteps) {
          canvas.drawLine(
            Offset(cellLeft + cellWidth - cellPad, vertPad + 4),
            Offset(cellLeft + cellWidth - cellPad, kTrackRowHeight - vertPad - 4),
            _dividerPaint,
          );
        }
      }
    }
  }

  void _drawDividendIcon(Canvas canvas, double left, Color companyColor) {
    final cx = left + _kDividendWidth / 2;
    final cy = kTrackRowHeight / 2;

    // Circular background.
    final iconPaint = Paint()..color = companyColor.withValues(alpha: 0.15);
    canvas.drawCircle(Offset(cx, cy), 14, iconPaint);

    // Dollar coin — circle with "$" text.
    final coinPaint = Paint()
      ..color = companyColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawCircle(Offset(cx, cy), 9, coinPaint);

    final dollarPainter = TextPainter(
      text: TextSpan(
        text: '\$',
        style: TextStyle(
          color: companyColor.withValues(alpha: 0.8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    dollarPainter.paint(
      canvas,
      Offset(cx - dollarPainter.width / 2, cy - dollarPainter.height / 2),
    );
  }

  void _drawMonogram(
    Canvas canvas,
    double left,
    double top,
    double areaWidth,
  ) {
    final letter = (kCompanyShort[companyId] ?? companyId.toUpperCase())[0];
    final painter = TextPainter(
      text: TextSpan(
        text: letter,
        style: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        left + (areaWidth - painter.width) / 2,
        (kTrackRowHeight - painter.height) / 2,
      ),
    );
  }
}
