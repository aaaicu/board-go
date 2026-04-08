import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/client/gamenode/gamenode_screen.dart';
import '../../lib/client/gamenode/discovery_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('GameNodeScreen', () {
    testWidgets('shows discovery screen when not connected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameNodeScreen()),
      );
      // Allow PlayerIdentity.load() to complete.
      await tester.pumpAndSettle();

      expect(find.byType(DiscoveryScreen), findsOneWidget);
    });

    testWidgets('discovery phase shows no AppBar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameNodeScreen()),
      );
      await tester.pumpAndSettle();
      // The GameNodeScreen no longer uses an AppBar — it shows a custom
      // identity bar only in lobby/game phases, not during discovery.
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('discovery phase does not show edit icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameNodeScreen()),
      );
      await tester.pumpAndSettle();

      // The edit icon only appears in the identity bar during lobby phase.
      // During discovery, neither AppBar nor identity bar is rendered.
      expect(find.byIcon(Icons.edit), findsNothing);
    });
  });

  group('DiscoveryScreen', () {
    testWidgets('shows a "Scan QR" button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiscoveryScreen()),
        ),
      );

      expect(find.text('QR 코드 스캔'), findsOneWidget);
    });

    testWidgets('shows a "Search for servers" button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiscoveryScreen()),
        ),
      );

      expect(find.text('주변 서버 자동 탐색'), findsOneWidget);
    });

    testWidgets('shows IP input field and connect button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiscoveryScreen()),
        ),
      );

      expect(find.text('IP 직접 입력'), findsOneWidget);
      expect(find.text('접속'), findsOneWidget);
    });

    testWidgets('connect button calls onServerSelected with correct ws URL',
        (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoveryScreen(onServerSelected: (url) => selected = url),
          ),
        ),
      );

      // Clear and enter custom IP/port
      await tester.enterText(find.widgetWithText(TextField, 'IP 주소'), '10.0.0.1');
      await tester.enterText(
          find.widgetWithText(TextField, '포트'), '8080');
      await tester.tap(find.text('접속'));
      await tester.pump();

      expect(selected, equals('ws://10.0.0.1:8080/ws'));
    });

    testWidgets('tapping "Search" triggers onSearch callback', (tester) async {
      var searchCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscoveryScreen(onSearch: () => searchCalled = true),
          ),
        ),
      );

      await tester.tap(find.text('주변 서버 자동 탐색'));
      await tester.pump();

      expect(searchCalled, isTrue);
    });
  });
}
