import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// Deep dark wood/table background rendered procedurally via Canvas.
///
/// Fills a fixed world-space rectangle large enough that the camera will
/// never see the edge at any supported zoom level.  Grain dots are seeded
/// once at construction time so they do not flicker between frames.
class TableBackgroundComponent extends PositionComponent {
  static const double _kHalfSize = 2000.0;
  static const Color _kBaseColor = Color(0xFF1A1008);

  /// Pre-computed grain dot positions (relative to component origin).
  final List<Offset> _grainDots;

  TableBackgroundComponent() : _grainDots = _buildGrain() {
    size = Vector2.all(_kHalfSize * 2);
    position = Vector2.all(-_kHalfSize);
    priority = -100; // always behind everything else
  }

  // ---------------------------------------------------------------------------
  // Pre-compute 1200 grain dots once — no rand calls in render().
  // ---------------------------------------------------------------------------
  static List<Offset> _buildGrain() {
    final rand = math.Random(42);
    final side = _kHalfSize * 2;
    return List.generate(
      1200,
      (_) => Offset(rand.nextDouble() * side, rand.nextDouble() * side),
    );
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);

    // Base fill.
    canvas.drawRect(rect, Paint()..color = _kBaseColor);

    // Subtle wood-grain gradient — horizontal bands.
    final grainGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFF1A1008),
        Color(0xFF221408),
        Color(0xFF1A1008),
        Color(0xFF1E1208),
        Color(0xFF1A1008),
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = grainGradient.createShader(rect),
    );

    // Grain dots — very faint, two sizes.
    final smallDotPaint = Paint()..color = const Color(0x0DFFFFFF);
    final largeDotPaint = Paint()..color = const Color(0x08FFFFFF);

    for (var i = 0; i < _grainDots.length; i++) {
      final dot = _grainDots[i];
      if (i % 5 == 0) {
        canvas.drawCircle(dot, 1.2, largeDotPaint);
      } else {
        canvas.drawCircle(dot, 0.6, smallDotPaint);
      }
    }

    // Vignette — slightly darker towards corners.
    final vignetteGradient = RadialGradient(
      center: Alignment.center,
      radius: 0.85,
      colors: const [
        Color(0x00000000),
        Color(0x55000000),
      ],
    );
    canvas.drawRect(
      rect,
      Paint()..shader = vignetteGradient.createShader(rect),
    );
  }
}
