import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/main.dart';
import '../../lib/client/gameboard/gameboard_screen.dart';
import '../../lib/client/gamenode/gamenode_screen.dart';

void main() {
  group('RoleSelectScreen', () {
    testWidgets('shows "board-go" title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RoleSelectScreen()));
      expect(find.text('board-go'), findsOneWidget);
    });

    testWidgets('shows 게임 보드 and 플레이어 cards', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RoleSelectScreen()));
      expect(find.text('게임 보드'), findsOneWidget);
      expect(find.text('플레이어'), findsOneWidget);
    });

    testWidgets('tapping 게임 보드 navigates to GameboardScreen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RoleSelectScreen()));
      await tester.tap(find.text('게임 보드'));
      // pump + advance past the route transition animation (300 ms default).
      // We do NOT pumpAndSettle because GameboardScreen starts a real Isolate.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GameboardScreen), findsOneWidget);
    });

    testWidgets('tapping 플레이어 navigates to GameNodeScreen', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RoleSelectScreen()));
      await tester.tap(find.text('플레이어'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GameNodeScreen), findsOneWidget);
    });
  });
}
