import 'package:test/test.dart';

import '../../lib/shared/game_session/game_log_entry.dart';
import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/player_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PlayerSessionState _makePlayer({
  String playerId = 'p1',
  String nickname = 'Alice',
  bool isConnected = true,
  bool isReady = false,
  String reconnectToken = 'token-abc',
}) =>
    PlayerSessionState(
      playerId: playerId,
      nickname: nickname,
      isConnected: isConnected,
      isReady: isReady,
      reconnectToken: reconnectToken,
    );

GameSessionState _makeSession({
  String sessionId = 'session-1',
  SessionPhase phase = SessionPhase.lobby,
  Map<String, PlayerSessionState>? players,
  List<String>? playerOrder,
  int version = 0,
  List<GameLogEntry>? log,
}) =>
    GameSessionState(
      sessionId: sessionId,
      phase: phase,
      players: players ?? {},
      playerOrder: playerOrder ?? [],
      version: version,
      log: log ?? [],
    );

GameLogEntry _makeLog({
  String eventType = 'PLAYER_JOINED',
  String description = 'Alice joined',
  int? timestamp,
}) =>
    GameLogEntry(
      eventType: eventType,
      description: description,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionPhase', () {
    test('toJson / fromJson round-trip for all values', () {
      for (final phase in SessionPhase.values) {
        expect(SessionPhase.fromJson(phase.toJson()), equals(phase));
      }
    });

    test('fromJson throws on unknown value', () {
      expect(() => SessionPhase.fromJson('UNKNOWN'), throwsFormatException);
    });
  });

  group('PlayerSessionState', () {
    test('constructs with expected field values', () {
      final player = _makePlayer();
      expect(player.playerId, equals('p1'));
      expect(player.nickname, equals('Alice'));
      expect(player.isConnected, isTrue);
      expect(player.isReady, isFalse);
      expect(player.reconnectToken, equals('token-abc'));
    });

    test('copyWith changes only specified fields', () {
      final original = _makePlayer();
      final updated = original.copyWith(isReady: true, nickname: 'Alice2');
      expect(updated.isReady, isTrue);
      expect(updated.nickname, equals('Alice2'));
      expect(updated.playerId, equals('p1'));
      expect(updated.isConnected, isTrue);
      expect(updated.reconnectToken, equals('token-abc'));
    });

    test('toJson / fromJson round-trip', () {
      final player = _makePlayer();
      final json = player.toJson();
      final restored = PlayerSessionState.fromJson(json);

      expect(restored.playerId, equals(player.playerId));
      expect(restored.nickname, equals(player.nickname));
      expect(restored.isConnected, equals(player.isConnected));
      expect(restored.isReady, equals(player.isReady));
      expect(restored.reconnectToken, equals(player.reconnectToken));
    });

    test('two players with different reconnectTokens are distinct', () {
      final p1 = _makePlayer(reconnectToken: 'token-aaa');
      final p2 = _makePlayer(reconnectToken: 'token-bbb');
      expect(p1.reconnectToken, isNot(equals(p2.reconnectToken)));
    });
  });

  group('GameLogEntry', () {
    test('toJson / fromJson round-trip', () {
      final entry = _makeLog(timestamp: 1_700_000_000_000);
      final json = entry.toJson();
      final restored = GameLogEntry.fromJson(json);

      expect(restored.eventType, equals(entry.eventType));
      expect(restored.description, equals(entry.description));
      expect(restored.timestamp, equals(entry.timestamp));
    });
  });

  group('GameSessionState', () {
    test('default construction has expected values', () {
      final state = _makeSession();
      expect(state.sessionId, equals('session-1'));
      expect(state.phase, equals(SessionPhase.lobby));
      expect(state.players, isEmpty);
      expect(state.playerOrder, isEmpty);
      expect(state.version, equals(0));
      expect(state.log, isEmpty);
    });

    test('copyWith changes phase and increments nothing automatically', () {
      final state = _makeSession();
      final updated = state.copyWith(phase: SessionPhase.inGame);
      expect(updated.phase, equals(SessionPhase.inGame));
      // copyWith is a plain copy — version increment is the caller's
      // responsibility; addLog does it automatically.
      expect(updated.version, equals(0));
      expect(updated.sessionId, equals('session-1'));
    });

    test('toJson / fromJson round-trip with players and log', () {
      final player = _makePlayer();
      final entry = _makeLog(timestamp: 1_700_000_000_000);
      final state = _makeSession(
        phase: SessionPhase.inGame,
        players: {'p1': player},
        playerOrder: ['p1'],
        version: 3,
        log: [entry],
      );

      final json = state.toJson();
      final restored = GameSessionState.fromJson(json);

      expect(restored.sessionId, equals(state.sessionId));
      expect(restored.phase, equals(SessionPhase.inGame));
      expect(restored.version, equals(3));
      expect(restored.playerOrder, equals(['p1']));
      expect(restored.players.length, equals(1));
      expect(restored.players['p1']?.nickname, equals('Alice'));
      expect(restored.log.length, equals(1));
      expect(restored.log.first.eventType, equals('PLAYER_JOINED'));
    });

    test('addLog appends an entry and bumps version', () {
      final state = _makeSession(version: 5);
      final entry = _makeLog();
      final updated = state.addLog(entry);

      expect(updated.log.length, equals(1));
      expect(updated.version, equals(6));
    });

    test('addLog trims log to 50 entries when limit is exceeded', () {
      // Create a session with exactly 50 log entries already.
      final entries = List.generate(
        50,
        (i) => _makeLog(eventType: 'EVENT_$i', timestamp: 1_000 + i),
      );
      final state = _makeSession(log: entries, version: 50);

      // Adding one more should evict the oldest (EVENT_0).
      final overflow = _makeLog(eventType: 'EVENT_NEW', timestamp: 2_000);
      final updated = state.addLog(overflow);

      expect(updated.log.length, equals(50));
      expect(updated.log.first.eventType, equals('EVENT_1'));
      expect(updated.log.last.eventType, equals('EVENT_NEW'));
    });

    test('addLog with 49 entries keeps all 50 after one more', () {
      final entries = List.generate(
        49,
        (i) => _makeLog(timestamp: 1_000 + i),
      );
      final state = _makeSession(log: entries);
      final updated = state.addLog(_makeLog(eventType: 'FINAL'));

      expect(updated.log.length, equals(50));
      expect(updated.log.last.eventType, equals('FINAL'));
    });
  });
}
