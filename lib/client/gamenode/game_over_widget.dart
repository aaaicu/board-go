import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../../shared/game_pack/views/player_view.dart';

/// Displayed when [PlayerView.phase] is [SessionPhase.finished].
class GameOverWidget extends StatelessWidget {
  final PlayerView playerView;
  final VoidCallback onMainMenu;

  const GameOverWidget({
    super.key,
    required this.playerView,
    required this.onMainMenu,
  });

  @override
  Widget build(BuildContext context) {
    final pv = playerView;
    final maxScore = pv.scores.values.fold(0, max);
    final winners = pv.scores.entries
        .where((e) => e.value == maxScore)
        .map((e) => e.key)
        .toList();
    final isWinner = winners.contains(pv.playerId);

    final sortedScores = pv.scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isWinner ? Icons.emoji_events : Icons.sentiment_neutral,
            size: 64,
            color: isWinner ? Colors.amber : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            isWinner ? '승리!' : '게임 종료',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          for (final e in sortedScores)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${e.key == pv.playerId ? "나" : e.key}: ${e.value}점',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: e.key == pv.playerId
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: onMainMenu,
            child: const Text('메인으로'),
          ),
        ],
      ),
    );
  }
}
