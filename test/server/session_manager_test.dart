import 'dart:async';

import 'package:test/test.dart';

import '../../lib/server/session_manager.dart';

/// Lightweight in-memory sink stub for testing.
class _FakeSink implements SessionSink {
  final List<String> sent = [];
  bool closed = false;

  @override
  void add(String data) {
    if (!closed) sent.add(data);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  group('SessionManager', () {
    late SessionManager manager;

    setUp(() {
      manager = SessionManager();
    });

    test('registers a new player session', () {
      final sink = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink);

      expect(manager.isConnected('p1'), isTrue);
      expect(manager.playerCount, equals(1));
    });

    test('unregisters a player session', () {
      final sink = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink);
      manager.unregister('p1');

      expect(manager.isConnected('p1'), isFalse);
      expect(manager.playerCount, equals(0));
    });

    test('send delivers message to the correct player', () {
      final sink1 = _FakeSink();
      final sink2 = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink1);
      manager.register(playerId: 'p2', displayName: 'Bob', sink: sink2);

      manager.send('p1', 'hello-p1');

      expect(sink1.sent, equals(['hello-p1']));
      expect(sink2.sent, isEmpty);
    });

    test('broadcast delivers message to all connected players', () {
      final sink1 = _FakeSink();
      final sink2 = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink1);
      manager.register(playerId: 'p2', displayName: 'Bob', sink: sink2);

      manager.broadcast('state-update');

      expect(sink1.sent, equals(['state-update']));
      expect(sink2.sent, equals(['state-update']));
    });

    test('broadcast excludes specified player', () {
      final sink1 = _FakeSink();
      final sink2 = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink1);
      manager.register(playerId: 'p2', displayName: 'Bob', sink: sink2);

      manager.broadcast('state-update', excludePlayerId: 'p1');

      expect(sink1.sent, isEmpty);
      expect(sink2.sent, equals(['state-update']));
    });

    test('send to unknown player is a no-op (no exception)', () {
      expect(() => manager.send('unknown', 'msg'), returnsNormally);
    });

    test('registering duplicate playerId overwrites the old session', () {
      final sink1 = _FakeSink();
      final sink2 = _FakeSink();
      manager.register(playerId: 'p1', displayName: 'Alice', sink: sink1);
      manager.register(playerId: 'p1', displayName: 'Alice2', sink: sink2);

      manager.send('p1', 'msg');

      // Only the new sink should receive the message
      expect(sink1.sent, isEmpty);
      expect(sink2.sent, equals(['msg']));
      expect(manager.playerCount, equals(1));
    });

    test('playerIds returns all connected player ids', () {
      manager.register(
        playerId: 'p1',
        displayName: 'Alice',
        sink: _FakeSink(),
      );
      manager.register(playerId: 'p2', displayName: 'Bob', sink: _FakeSink());

      expect(manager.playerIds, containsAll(['p1', 'p2']));
    });

    test('displayName returns the correct name for a player', () {
      manager.register(
        playerId: 'p1',
        displayName: 'Alice',
        sink: _FakeSink(),
      );
      expect(manager.displayName('p1'), equals('Alice'));
    });

    test('displayName returns null for unknown player', () {
      expect(manager.displayName('nobody'), isNull);
    });
  });
}
