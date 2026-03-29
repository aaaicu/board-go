import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../shared/game_pack/views/board_view.dart';
import 'flame/secret_hitler/secret_hitler_board_game.dart';

class SecretHitlerBoardWidget extends StatefulWidget {
  final BoardView boardView;
  final Map<String, String> playerNames;

  const SecretHitlerBoardWidget({
    super.key,
    required this.boardView,
    required this.playerNames,
  });

  @override
  State<SecretHitlerBoardWidget> createState() => _SecretHitlerBoardWidgetState();
}

class _SecretHitlerBoardWidgetState extends State<SecretHitlerBoardWidget> {
  late final SecretHitlerBoardGame _game;

  @override
  void initState() {
    super.initState();
    _game = SecretHitlerBoardGame(
      latestView: widget.boardView,
      playerNames: widget.playerNames,
    );
  }

  @override
  void didUpdateWidget(SecretHitlerBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardView != widget.boardView) {
      _game.updateView(widget.boardView);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget(game: _game);
  }
}
