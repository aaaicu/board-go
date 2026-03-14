import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/client/gamenode/game_over_widget.dart';
import '../../lib/shared/game_pack/views/player_view.dart';
import '../../lib/shared/game_session/session_phase.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PlayerView _makeView({
  required String playerId,
  required Map<String, int> scores,
}) =>
    PlayerView(
      phase: SessionPhase.finished,
      playerId: playerId,
      hand: const [],
      scores: scores,
      turnState: null,
      allowedActions: const [],
      version: 1,
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GameOverWidget', () {
    testWidgets('renders game-over UI for finished phase', (tester) async {
      final pv = _makeView(playerId: 'p1', scores: {'p1': 3, 'p2': 5});

      await tester.pumpWidget(
        _wrap(GameOverWidget(playerView: pv, onMainMenu: () {})),
      );

      // Either '승리!' or '게임 종료' is present — confirms game-over UI is shown.
      expect(
        find.textContaining(RegExp(r'승리!|게임 종료')),
        findsOneWidget,
      );
      // '메인으로' button is present.
      expect(find.text('메인으로'), findsOneWidget);
    });

    testWidgets('shows 승리! for the winning player', (tester) async {
      final pv = _makeView(playerId: 'p1', scores: {'p1': 7, 'p2': 3});

      await tester.pumpWidget(
        _wrap(GameOverWidget(playerView: pv, onMainMenu: () {})),
      );

      expect(find.text('승리!'), findsOneWidget);
      expect(find.text('게임 종료'), findsNothing);
    });

    testWidgets('shows 게임 종료 for the losing player', (tester) async {
      final pv = _makeView(playerId: 'p2', scores: {'p1': 7, 'p2': 3});

      await tester.pumpWidget(
        _wrap(GameOverWidget(playerView: pv, onMainMenu: () {})),
      );

      expect(find.text('게임 종료'), findsOneWidget);
      expect(find.text('승리!'), findsNothing);
    });

    testWidgets('tapping 메인으로 calls onMainMenu callback', (tester) async {
      var called = false;
      final pv = _makeView(playerId: 'p1', scores: {'p1': 5});

      await tester.pumpWidget(
        _wrap(
          GameOverWidget(
            playerView: pv,
            onMainMenu: () => called = true,
          ),
        ),
      );

      await tester.tap(find.text('메인으로'));
      await tester.pump();

      expect(called, isTrue);
    });

    testWidgets('displays scores for all players', (tester) async {
      final pv = _makeView(
        playerId: 'p1',
        scores: {'p1': 4, 'p2': 6},
      );

      await tester.pumpWidget(
        _wrap(GameOverWidget(playerView: pv, onMainMenu: () {})),
      );

      // Own score shows as "나: N점".
      expect(find.textContaining('나: 4점'), findsOneWidget);
      // Opponent score shows as "p2: N점".
      expect(find.textContaining('p2: 6점'), findsOneWidget);
    });
  });
}
