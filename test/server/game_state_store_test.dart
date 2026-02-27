import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import '../../lib/server/game_state_store.dart';
import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/player_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GameSessionState _makeState({
  String sessionId = 'session-1',
  int version = 1,
  SessionPhase phase = SessionPhase.lobby,
  Map<String, PlayerSessionState>? players,
}) =>
    GameSessionState(
      sessionId: sessionId,
      phase: phase,
      players: players ?? {},
      playerOrder: players?.keys.toList() ?? [],
      version: version,
      log: const [],
    );

PlayerSessionState _makePlayer(String id) => PlayerSessionState(
      playerId: id,
      nickname: 'Player $id',
      isConnected: true,
      isReady: false,
      reconnectToken: 'token-$id',
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('GameStateStore', () {
    late GameStateStore store;

    setUp(() async {
      store = GameStateStore();
      await store.open();
    });

    tearDown(() async => store.close());

    test('load() returns null for an unknown sessionId', () async {
      final result = await store.load('nonexistent');
      expect(result, isNull);
    });

    test('save() then load() returns the same state', () async {
      final state = _makeState(sessionId: 'abc', version: 7);
      await store.save(state);

      final loaded = await store.load('abc');
      expect(loaded, isNotNull);
      expect(loaded!.sessionId, equals('abc'));
      expect(loaded.version, equals(7));
      expect(loaded.phase, equals(SessionPhase.lobby));
    });

    test('save() persists player list', () async {
      final state = _makeState(
        sessionId: 's1',
        players: {'p1': _makePlayer('p1'), 'p2': _makePlayer('p2')},
      );
      await store.save(state);

      final loaded = await store.load('s1');
      expect(loaded!.players.length, equals(2));
      expect(loaded.players.containsKey('p1'), isTrue);
      expect(loaded.players.containsKey('p2'), isTrue);
    });

    test('second save() overwrites the first (upsert semantics)', () async {
      final v1 = _makeState(sessionId: 'upsert', version: 1);
      final v2 = _makeState(
          sessionId: 'upsert', version: 2, phase: SessionPhase.inGame);

      await store.save(v1);
      await store.save(v2);

      final loaded = await store.load('upsert');
      expect(loaded!.version, equals(2));
      expect(loaded.phase, equals(SessionPhase.inGame));
    });

    test('delete() removes the record; subsequent load() returns null',
        () async {
      final state = _makeState(sessionId: 'to-delete');
      await store.save(state);

      await store.delete('to-delete');

      final loaded = await store.load('to-delete');
      expect(loaded, isNull);
    });

    test('delete() on non-existent sessionId does not throw', () async {
      expect(() => store.delete('ghost'), returnsNormally);
    });

    test('multiple sessions can coexist independently', () async {
      await store.save(_makeState(sessionId: 'A', version: 10));
      await store.save(_makeState(sessionId: 'B', version: 20));

      final a = await store.load('A');
      final b = await store.load('B');

      expect(a!.version, equals(10));
      expect(b!.version, equals(20));
    });
  });
}
