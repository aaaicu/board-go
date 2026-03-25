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

const Map<String, Color> kCompanyColors = {
  'aauto': Color(0xFF6B9FD4),
  'epic': Color(0xFF6BBF6B),
  'fed': Color(0xFFB5845A),
  'lehm': Color(0xFFAB82C5),
  'sip': Color(0xFFE8A857),
  'tot': Color(0xFFE87D9A),
};

const Map<String, String> kCompanyShort = {
  'aauto': 'AAUTO',
  'epic': 'EPIC',
  'fed': 'FED',
  'lehm': 'LEHM',
  'sip': 'SIP',
  'tot': 'TOT',
};

/// Returns the sprite asset path for a company logo.
String companyImagePath(String companyId) =>
    'gamepacks/stockpile/image/${companyShort(companyId)}.png';

/// Returns the short ticker symbol for a company.
String companyShort(String companyId) =>
    kCompanyShort[companyId] ?? companyId.toUpperCase();

// ---------------------------------------------------------------------------
// Price colour rules
// ---------------------------------------------------------------------------
Color _priceColor(int price) {
  if (price <= 3) return const Color(0xFFE05252); // red — danger
  if (price >= 9) return const Color(0xFFFFD700); // gold — peak
  return const Color(0xFFFFFFFF); // white — normal
}

// ---------------------------------------------------------------------------
// StockPriceTileComponent
// ---------------------------------------------------------------------------

/// A physical-looking company stock tile (80 × 100 world units).
///
/// Layout:
///   - Upper 60 %: company logo sprite
///   - Lower 40 %: ticker symbol + current price
///
/// The tile carries a [Sprite] loaded asynchronously.  Before the sprite is
/// available the company colour fills the upper area.
class StockPriceTileComponent extends PositionComponent {
  static const double kTileWidth = 80.0;
  static const double kTileHeight = 100.0;
  static const double _kCornerRadius = 8.0;
  static const double _kLogoRatio = 0.60;
  static const double _kShadowOffset = 3.0;
  static const double _kBorderWidth = 2.0;

  final String companyId;
  int price;

  Sprite? _logoSprite;

  // Pre-allocated paint objects — reused every frame.
  final Paint _shadowPaint = Paint()..color = const Color(0x66000000);
  final Paint _bgPaint = Paint();
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _kBorderWidth;
  final Paint _logoBgPaint = Paint();
  final Paint _footerBgPaint = Paint();

  StockPriceTileComponent({
    required this.companyId,
    required this.price,
    required Vector2 position,
  }) : super(
          size: Vector2(kTileWidth, kTileHeight),
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
      // Logo unavailable — fallback colour fill is already handled in render().
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Updates the displayed price.  Call this instead of mutating [price]
  /// directly so the component can later add tween effects here.
  void updatePrice(int newPrice) {
    price = newPrice;
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final companyColor = kCompanyColors[companyId] ?? const Color(0xFF888888);
    final tileRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, kTileWidth, kTileHeight),
      const Radius.circular(_kCornerRadius),
    );

    // Drop shadow.
    final shadowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          _kShadowOffset, _kShadowOffset, kTileWidth, kTileHeight),
      const Radius.circular(_kCornerRadius),
    );
    canvas.drawRRect(shadowRect, _shadowPaint);

    // Tile body — slightly darkened version of company colour.
    _bgPaint.color = _darken(companyColor, 0.25);
    canvas.drawRRect(tileRect, _bgPaint);

    // Logo area — original company colour.
    final logoHeight = kTileHeight * _kLogoRatio;
    final logoRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, kTileWidth, logoHeight),
      const Radius.circular(_kCornerRadius),
    );
    _logoBgPaint.color = companyColor;
    canvas.drawRRect(logoRect, _logoBgPaint);

    // Sprite or placeholder.
    if (_logoSprite != null) {
      const padding = 6.0;
      _logoSprite!.render(
        canvas,
        position: Vector2(padding, padding),
        size: Vector2(kTileWidth - padding * 2, logoHeight - padding * 2),
      );
    } else {
      // Monogram fallback while the image loads.
      _drawMonogram(canvas, companyId, logoHeight);
    }

    // Footer background.
    final footerY = logoHeight;
    final footerHeight = kTileHeight - logoHeight;
    final footerRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, footerY, kTileWidth, footerHeight),
      const Radius.circular(_kCornerRadius),
    );
    _footerBgPaint.color = const Color(0xFF1A1008);
    canvas.drawRRect(footerRRect, _footerBgPaint);

    // Ticker label.
    final tickerPainter = TextPainter(
      text: TextSpan(
        text: kCompanyShort[companyId] ?? companyId.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFCCCCCC),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tickerPainter.paint(
      canvas,
      Offset(
        (kTileWidth - tickerPainter.width) / 2,
        footerY + 4,
      ),
    );

    // Price label.
    final priceText = '\$$price';
    final pricePainter = TextPainter(
      text: TextSpan(
        text: priceText,
        style: TextStyle(
          color: _priceColor(price),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pricePainter.paint(
      canvas,
      Offset(
        (kTileWidth - pricePainter.width) / 2,
        footerY + 18,
      ),
    );

    // Tile border — company colour tinted.
    _borderPaint.color = companyColor.withValues(alpha: 180 / 255);
    canvas.drawRRect(tileRect, _borderPaint);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _drawMonogram(Canvas canvas, String id, double logoHeight) {
    final letter = (kCompanyShort[id] ?? id.toUpperCase())[0];
    final painter = TextPainter(
      text: TextSpan(
        text: letter,
        style: const TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (kTileWidth - painter.width) / 2,
        (logoHeight - painter.height) / 2,
      ),
    );
  }

  /// Returns a darker version of [color] by reducing brightness by [amount].
  Color _darken(Color color, double amount) {
    assert(amount >= 0 && amount <= 1);
    final f = 1.0 - amount;
    return Color.fromARGB(
      (color.a * 255.0).round().clamp(0, 255),
      (color.r * 255.0 * f).round().clamp(0, 255),
      (color.g * 255.0 * f).round().clamp(0, 255),
      (color.b * 255.0 * f).round().clamp(0, 255),
    );
  }
}
