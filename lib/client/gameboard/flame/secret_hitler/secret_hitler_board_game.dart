import 'package:flutter/material.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/palette.dart';
import '../../../../shared/game_session/session_phase.dart';
import '../../../../shared/game_pack/views/board_view.dart';
import '../../../shared/app_theme.dart';

class SecretHitlerBoardGame extends FlameGame {
  BoardView latestView;
  final Map<String, String> playerNames;

  SecretHitlerBoardGame({
    required this.latestView,
    required this.playerNames,
  });

  late _TableComponent _table;
  late TextComponent _statusText;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Setup Camera
    camera.viewfinder.position = Vector2(0, 0);
    camera.viewfinder.anchor = Anchor.center;

    // Draw the 2.5D wooden table
    _table = _TableComponent()
      ..position = Vector2(0, 0)
      ..anchor = Anchor.center
      ..size = Vector2(800, 400); // Elliptical perspective
    world.add(_table);

    _statusText = TextComponent(
      text: 'Secret Hitler 2.5D Board',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    )..anchor = Anchor.center
     ..position = Vector2(0, -150);
    world.add(_statusText);

    // Initial sync
    _syncWithView();
  }

  void updateView(BoardView newView) {
    latestView = newView;
    _syncWithView();
  }

  void _syncWithView() {
    final data = latestView.data;
    
    // Update simple status
    final phase = data['phase'] as String? ?? 'UNKNOWN';
    final liberal = data['liberalPolicies'] as int? ?? 0;
    final fascist = data['fascistPolicies'] as int? ?? 0;
    final tracker = data['electionTracker'] as int? ?? 0;
    
    _statusText.text = 'Phase: $phase\nLiberal: $liberal | Fascist: $fascist\nTracker: $tracker/3';
  }
}

class _TableComponent extends PositionComponent {
  final _paintWood = BasicPalette.brown.paint()..style = PaintingStyle.fill;
  final _paintRim = Paint()..color = const Color(0xFF3E2723)..style = PaintingStyle.stroke..strokeWidth = 10;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Draw 2.5D isometric table
    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawOval(rect, _paintWood);
    canvas.drawOval(rect, _paintRim);
  }
}
