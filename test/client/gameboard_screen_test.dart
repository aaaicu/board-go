import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/client/gameboard/gameboard_screen.dart';
import '../../lib/client/gameboard/server_status_widget.dart';
import '../../lib/client/gameboard/qr_code_widget.dart';
import '../../lib/server/server_isolate.dart';

/// Lightweight fake handle — no sockets, no isolates.
class _FakeHandle implements ServerHandle {
  @override
  final int port = 12345;
  @override
  bool isRunning = true;

  final StreamController<PlayerEvent> events =
      StreamController<PlayerEvent>.broadcast();

  @override
  Stream<PlayerEvent> get playerEvents => events.stream;

  @override
  Future<void> stop() async {
    isRunning = false;
    await events.close();
  }
}

void main() {
  group('GameboardScreen', () {
    testWidgets('shows loading indicator while server is starting',
        (tester) async {
      // Completer that never completes → server stays "starting" forever.
      // Unlike Future.delayed this does not register a Dart Timer.
      final completer = Completer<ServerHandle>();

      await tester.pumpWidget(
        MaterialApp(
          home: GameboardScreen(serverStarter: () => completer.future),
        ),
      );

      // On the very first frame the future hasn't resolved → loading shown.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the completer in teardown so Flutter doesn't complain about
      // dangling futures.
      completer.complete(_FakeHandle());
    });

    testWidgets('shows ServerStatusWidget once server is running',
        (tester) async {
      // tester.runAsync lets real-world async (NetworkInterface.list) run.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => _FakeHandle()),
          ),
        );
        // Give async operations time to complete.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.byType(ServerStatusWidget), findsOneWidget);
    });

    testWidgets('shows QrCodeWidget once server is running', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => _FakeHandle()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.byType(QrCodeWidget), findsOneWidget);
    });

    testWidgets('AppBar title is "board-go"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GameboardScreen(
              serverStarter: () => Completer<ServerHandle>().future),
        ),
      );
      expect(find.text('board-go'), findsOneWidget);
    });

    testWidgets('displays the server port in the status widget', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => _FakeHandle()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.textContaining('12345'), findsWidgets);
    });

    testWidgets('player name appears when join event received', (tester) async {
      late _FakeHandle handle;
      await tester.runAsync(() async {
        handle = _FakeHandle();
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => handle),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        handle.events.add(const PlayerEvent(
          joined: true,
          playerId: 'p1',
          displayName: 'Alice',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('player name removed when leave event received', (tester) async {
      late _FakeHandle handle;
      await tester.runAsync(() async {
        handle = _FakeHandle();
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => handle),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        handle.events.add(const PlayerEvent(
          joined: true,
          playerId: 'p1',
          displayName: 'Alice',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);

      await tester.runAsync(() async {
        handle.events.add(const PlayerEvent(
          joined: false,
          playerId: 'p1',
          displayName: 'Alice',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('both players shown when two join with same displayName',
        (tester) async {
      late _FakeHandle handle;
      await tester.runAsync(() async {
        handle = _FakeHandle();
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => handle),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        handle.events.add(const PlayerEvent(
          joined: true,
          playerId: 'p1',
          displayName: 'Player',
        ));
        handle.events.add(const PlayerEvent(
          joined: true,
          playerId: 'p2',
          displayName: 'Player',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // Both players must be tracked — count should be 2
      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets('player count correct after one of two same-named players leaves',
        (tester) async {
      late _FakeHandle handle;
      await tester.runAsync(() async {
        handle = _FakeHandle();
        await tester.pumpWidget(
          MaterialApp(
            home: GameboardScreen(serverStarter: () async => handle),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        handle.events.add(const PlayerEvent(
          joined: true,
          playerId: 'p1',
          displayName: 'Player',
        ));
        handle.events.add(const PlayerEvent(
          joined: true,
          playerId: 'p2',
          displayName: 'Player',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      // 2 players connected

      await tester.runAsync(() async {
        // p1 leaves
        handle.events.add(const PlayerEvent(
          joined: false,
          playerId: 'p1',
          displayName: 'Player',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      // p2 still connected — status label must show exactly 1
      expect(find.text('Players connected: 1'), findsOneWidget);
      // Player count of 0 must not appear in the status label
      expect(find.text('Players connected: 0'), findsNothing);
    });
  });

  group('ServerStatusWidget', () {
    testWidgets('displays player count and port', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerStatusWidget(
              port: 8080,
              playerCount: 3,
              playerNames: ['Alice', 'Bob', 'Carol'],
            ),
          ),
        ),
      );

      expect(find.textContaining('8080'), findsOneWidget);
      expect(find.textContaining('3'), findsWidgets);
    });

    testWidgets('lists connected player names', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerStatusWidget(
              port: 8080,
              playerCount: 2,
              playerNames: ['Alice', 'Bob'],
            ),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });
  });
}
