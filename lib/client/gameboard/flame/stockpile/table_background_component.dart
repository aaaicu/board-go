import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Cream/beige board background rendered procedurally via Canvas.
///
/// Mimics the warm parchment feel of the original Stockpile board game.
/// Fills a fixed world-space rectangle large enough that the camera never
/// sees the edge at any supported zoom level.  Subtle texture dots are
/// seeded once at construction time so they do not flicker between frames.
class TableBackgroundComponent extends PositionComponent {
  static const double _kHalfSize = 2000.0;

  /// Primary parchment / cream colour.
  static const Color _kBaseColor = Color(0xFFF5EFE0);

  /// Pre-computed texture dot positions (relative to component origin).
  final List<Offset> _textureDots;

  TableBackgroundComponent() : _textureDots = _buildTexture() {
    size = Vector2.all(_kHalfSize * 2);
    position = Vector2.all(-_kHalfSize);
    priority = -100; // always behind everything else
  }

  // ---------------------------------------------------------------------------
  // Pre-compute 800 texture dots once — no Random calls in render().
  // ---------------------------------------------------------------------------
  static List<Offset> _buildTexture() {
    final rand = math.Random(77);
    final side = _kHalfSize * 2;
    return List.generate(
      800,
      (_) => Offset(rand.nextDouble() * side, rand.nextDouble() * side),
    );
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Base cream fill.
    canvas.drawRect(rect, Paint()..color = _kBaseColor);

    // Subtle parchment gradient — very soft vertical banding.
    final grainGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [
        Color(0xFFF5EFE0),
        Color(0xFFEDE4CC),
        Color(0xFFF5EFE0),
        Color(0xFFEAE1CB),
        Color(0xFFF5EFE0),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = grainGradient.createShader(rect),
    );

    // Subtle paper-fibre texture dots in two shades.
    final lightDotPaint = Paint()..color = const Color(0x18A08060);
    final darkDotPaint = Paint()..color = const Color(0x10806040);

    for (var i = 0; i < _textureDots.length; i++) {
      final dot = _textureDots[i];
      if (i % 4 == 0) {
        canvas.drawCircle(dot, 1.0, darkDotPaint);
      } else {
        canvas.drawCircle(dot, 0.5, lightDotPaint);
      }
    }

    // Soft vignette — corners slightly darker for depth.
    final vignetteGradient = RadialGradient(
      center: Alignment.center,
      radius: 0.80,
      colors: const [
        Color(0x00000000),
        Color(0x28000000),
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = vignetteGradient.createShader(rect),
    );
  }
}
