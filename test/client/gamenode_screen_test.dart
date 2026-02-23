import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/client/gamenode/gamenode_screen.dart';
import '../../lib/client/gamenode/discovery_screen.dart';

void main() {
  group('GameNodeScreen', () {
    testWidgets('shows discovery screen when not connected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameNodeScreen()),
      );

      expect(find.byType(DiscoveryScreen), findsOneWidget);
    });

    testWidgets('AppBar title is "board-go"', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GameNodeScreen()),
      );
      expect(find.text('board-go'), findsOneWidget);
    });
  });

  group('DiscoveryScreen', () {
    testWidgets('shows a "Scan QR" button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiscoveryScreen()),
        ),
      );

      expect(find.text('Scan QR Code'), findsOneWidget);
    });

    testWidgets('shows a "Search for servers" button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DiscoveryScreen()),
        ),
      );

      expect(find.text('Search for Servers'), findsOneWidget);
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
      await tester.enterText(find.widgetWithText(TextField, 'IP'), '10.0.0.1');
      await tester.enterText(
          find.widgetWithText(TextField, 'Port'), '8080');
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

      await tester.tap(find.text('Search for Servers'));
      await tester.pump();

      expect(searchCalled, isTrue);
    });
  });
}
