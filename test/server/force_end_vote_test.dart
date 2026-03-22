import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/game_server.dart';
import '../../lib/server/server_isolate.dart';
import '../../lib/server/session_manager.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/messages/join_message.dart';
import '../../lib/shared/messages/join_room_ack_message.dart';
import '../../lib/shared/messages/ws_message.dart';

// ---------------------------------------------------------------------------
// Stubs
// ---------------------------------------------------------------------------

class _NoOpGamePack implements GamePackInterface {
  @override
  Future<void> initialize(GameState initialState) async {}
  @override
  bool validateAction(PlayerAction action, GameState currentState) => true;
  @override
  GameState processAction(PlayerAction action, GameState currentState) =>
      currentState;
  @override
  Future<void> dispose() async {}
}

class _FakeSink implements SessionSink {
  final List<String> sent = [];
  bool closed = false;

  @override
  void add(String data) => sent.add(data);

  @override
  Future<void> close() async => closed = true;

  /// Parses the last sent message as a [WsMessage].
  WsMessage? get lastMessage {
    if (sent.isEmpty) return null;
    try {
      return WsMessage.fromJson(
          jsonDecode(sent.last) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Returns all sent messages of a given type.
  List<WsMessage> messagesOfType(WsMessageType type) {
    return sent
        .map((raw) {
          try {
            return WsMessage.fromJson(
                jsonDecode(raw) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<WsMessage>()
        .where((m) => m.type == type)
        .toList();
  }
}

// ---------------------------------------------------------------------------
// WebSocket test client helper
// ---------------------------------------------------------------------------

class _WsClient {
  final WebSocketChannel _channel;
  final _controller = StreamController<WsMessage>.broadcast();

  _WsClient(this._channel) {
    _channel.stream.listen(
      (raw) {
        try {
          final msg = WsMessage.fromJson(
              jsonDecode(raw as String) as Map<String, dynamic>);
          if (!_controller.isClosed) _controller.add(msg);
        } catch (_) {}
      },
      onDone: () {
        if (!_controller.isClosed) _controller.close();
      },
    );
  }

  static Future<_WsClient> connect(int port) async {
    final ch = WebSocketChannel.connect(Uri.parse('ws://localhost:$port/ws'));
    await ch.ready;
    return _WsClient(ch);
  }

  void send(WsMessage msg) => _channel.sink.add(jsonEncode(msg.toJson()));

  Stream<WsMessage> get messages => _controller.stream;

  Future<WsMessage> next(WsMessageType type,
          {Duration timeout = const Duration(seconds: 5)}) =>
      messages.firstWhere((m) => m.type == type).timeout(timeout);

  Future<void> close() => _channel.sink.close();
}

GameState _defaultState() => GameState(
      gameId: 'vote-test',
      turn: 0,
      activePlayerId: '',
      data: {},
    );

// ---------------------------------------------------------------------------
// Helper: starts a game with two connected + ready players via WebSocket.
// Returns ([server], [client1], [client2]) with game already started.
// ---------------------------------------------------------------------------

Future<(GameServer, _WsClient, _WsClient)> _startGameWithTwoPlayers({
  Duration? voteTimeoutOverride,
}) async {
  final server = GameServer(
    gamePack: _NoOpGamePack(),
    voteTimeoutOverride: voteTimeoutOverride,
  );
  await server.start(
    host: 'localhost',
    port: 0,
    initialState: _defaultState(),
  );

  final c1 = await _WsClient.connect(server.port!);
  final c2 = await _WsClient.connect(server.port!);

  c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
  c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());
  await c1.next(WsMessageType.joinRoomAck);
  await c2.next(WsMessageType.joinRoomAck);

  c1.send(WsMessage(
      type: WsMessageType.setReady,
      payload: {'playerId': 'p1', 'isReady': true}));
  c2.send(WsMessage(
      type: WsMessageType.setReady,
      payload: {'playerId': 'p2', 'isReady': true}));

  server.startGame(packId: 'simple_card_battle');
  await c1.next(WsMessageType.playerView);

  return (server, c1, c2);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // 1. startForceEndVote in lobby does nothing
  // -------------------------------------------------------------------------

  group('1. startForceEndVote() is a no-op while in lobby', () {
    late GameServer server;
    late _FakeSink sink;

    setUp(() async {
      sink = _FakeSink();
      server = GameServer(gamePack: _NoOpGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: _defaultState(),
      );
      server.injectSessionForTest('p1', 'Alice', sink);
    });

    tearDown(() async => server.stop());

    test('no FORCE_END_VOTE_START is broadcast from lobby', () async {
      server.startForceEndVote();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final voteMsgs = sink.messagesOfType(WsMessageType.forceEndVoteStart);
      expect(voteMsgs, isEmpty,
          reason: 'startForceEndVote must be a no-op in lobby phase');
    });
  });

  // -------------------------------------------------------------------------
  // 2. startForceEndVote in game broadcasts FORCE_END_VOTE_START
  // -------------------------------------------------------------------------

  group('2. startForceEndVote() broadcasts FORCE_END_VOTE_START in game', () {
    late GameServer server;
    late _WsClient c1;
    late _WsClient c2;

    setUp(() async {
      (server, c1, c2) = await _startGameWithTwoPlayers();
    });

    tearDown(() async {
      await c1.close();
      await c2.close();
      await server.stop();
    });

    test('FORCE_END_VOTE_START is broadcast to all connected players', () async {
      // Arm listeners before triggering the event.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final voteStartFuture2 = c2.next(WsMessageType.forceEndVoteStart);

      server.startForceEndVote();

      final msg1 = await voteStartFuture1;
      final msg2 = await voteStartFuture2;

      expect(msg1.payload['playerCount'], equals(2));
      expect(msg2.payload['playerCount'], equals(2));
      expect(msg1.payload['timeoutSeconds'], equals(30));
    });

    test('second call while vote is active is ignored', () async {
      final startMessages = <WsMessage>[];
      final sub = c1.messages.listen((m) {
        if (m.type == WsMessageType.forceEndVoteStart) startMessages.add(m);
      });

      server.startForceEndVote();
      server.startForceEndVote(); // Should be ignored.

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(startMessages.length, equals(1),
          reason: 'Second startForceEndVote during active vote must be ignored');
    });
  });

  // -------------------------------------------------------------------------
  // 3. Votes from non-players are ignored
  // -------------------------------------------------------------------------

  group('3. Votes from unknown playerIds are ignored', () {
    late GameServer server;
    late _FakeSink sink;

    setUp(() async {
      sink = _FakeSink();
      server = GameServer(gamePack: _NoOpGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: _defaultState(),
      );
      server.injectSessionForTest('p1', 'Alice', sink);
    });

    tearDown(() async => server.stop());

    test('vote from unknown player does not trigger resolution', () async {
      // Start the game first.
      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);
      c1.send(
          JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());
      await c1.next(WsMessageType.joinRoomAck);
      await c2.next(WsMessageType.joinRoomAck);
      c1.send(WsMessage(
          type: WsMessageType.setReady,
          payload: {'playerId': 'p1', 'isReady': true}));
      c2.send(WsMessage(
          type: WsMessageType.setReady,
          payload: {'playerId': 'p2', 'isReady': true}));
      server.startGame(packId: 'simple_card_battle');
      await c1.next(WsMessageType.playerView);

      server.startForceEndVote();
      await c1.next(WsMessageType.forceEndVoteStart);

      // Vote from a player who isn't registered.
      server.handleMessageForTest(
        jsonEncode(WsMessage(
          type: WsMessageType.forceEndVote,
          payload: {'playerId': 'unknown-intruder', 'agree': true},
        ).toJson()),
        sink,
      );

      // No FORCE_END_VOTE_RESULT should have been broadcast yet.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final resultMsgs = sink.messagesOfType(WsMessageType.forceEndVoteResult);
      expect(resultMsgs, isEmpty,
          reason: 'Vote from non-player must be ignored');

      await c1.close();
      await c2.close();
    });
  });

  // -------------------------------------------------------------------------
  // 4. Majority agree → game resets to lobby
  // -------------------------------------------------------------------------

  group('4. Majority agree resolves vote and resets game', () {
    late GameServer server;
    late _WsClient c1;
    late _WsClient c2;

    setUp(() async {
      (server, c1, c2) = await _startGameWithTwoPlayers();
    });

    tearDown(() async {
      await c1.close();
      await c2.close();
      await server.stop();
    });

    test('both agree → FORCE_END_VOTE_RESULT agreed=true + GAME_RESET', () async {
      // Arm ALL listeners before triggering any server actions to avoid missing
      // fast messages on the loopback broadcast stream.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final voteStartFuture2 = c2.next(WsMessageType.forceEndVoteStart);
      final resultFuture = c1.next(WsMessageType.forceEndVoteResult);
      final resetFuture = c1.next(WsMessageType.gameReset);

      server.startForceEndVote();
      await voteStartFuture1;
      await voteStartFuture2;

      // Both vote agree.
      c1.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p1', 'agree': true},
      ));
      c2.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p2', 'agree': true},
      ));

      final result = await resultFuture;
      expect(result.payload['agreed'], isTrue);
      expect(result.payload['agreeCount'], equals(2));
      expect(result.payload['totalCount'], equals(2));

      // GAME_RESET must follow automatically.
      await resetFuture;
    });

    test('one agree out of two → not a strict majority (>50%)', () async {
      // Arm ALL listeners before triggering server actions.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final voteStartFuture2 = c2.next(WsMessageType.forceEndVoteStart);
      final resultFuture = c1.next(WsMessageType.forceEndVoteResult);

      server.startForceEndVote();
      await voteStartFuture1;
      await voteStartFuture2;

      // p1 agrees, p2 disagrees — 1 > 2/2 → 1 > 1.0 → false.
      // Strict majority requires more than half, so 1/2 is NOT enough.
      c1.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p1', 'agree': true},
      ));
      c2.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p2', 'agree': false},
      ));

      final result = await resultFuture;
      expect(result.payload['agreed'], isFalse,
          reason: '1/2 is not a strict majority (must be > 50%)');
      expect(result.payload['agreeCount'], equals(1));
    });
  });

  // -------------------------------------------------------------------------
  // 5. Minority/tie → vote fails, game continues
  // -------------------------------------------------------------------------

  group('5. Minority/tie vote fails — game continues', () {
    late GameServer server;
    late _WsClient c1;
    late _WsClient c2;

    setUp(() async {
      (server, c1, c2) = await _startGameWithTwoPlayers();
    });

    tearDown(() async {
      await c1.close();
      await c2.close();
      await server.stop();
    });

    test('both disagree → agreed=false, no GAME_RESET', () async {
      // Arm ALL listeners before triggering server actions.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final voteStartFuture2 = c2.next(WsMessageType.forceEndVoteStart);
      final resultFuture = c1.next(WsMessageType.forceEndVoteResult);

      server.startForceEndVote();
      await voteStartFuture1;
      await voteStartFuture2;

      c1.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p1', 'agree': false},
      ));
      c2.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p2', 'agree': false},
      ));

      final result = await resultFuture;
      expect(result.payload['agreed'], isFalse);

      // No GAME_RESET within 300ms.
      var resetReceived = false;
      final sub = c1.messages.listen((m) {
        if (m.type == WsMessageType.gameReset) resetReceived = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();

      expect(resetReceived, isFalse,
          reason: 'GAME_RESET must not be sent when vote fails');
    });
  });

  // -------------------------------------------------------------------------
  // 6. Second startForceEndVote while active is ignored
  //    (also tested inline in group 2 — redundant unit-style test here)
  // -------------------------------------------------------------------------

  group('6. startForceEndVote() is idempotent while a vote is active', () {
    late GameServer server;
    late _FakeSink sink1;
    late _FakeSink sink2;

    setUp(() async {
      sink1 = _FakeSink();
      sink2 = _FakeSink();
      server = GameServer(gamePack: _NoOpGamePack());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: _defaultState(),
      );
      server.injectSessionForTest('p1', 'Alice', sink1);
      server.injectSessionForTest('p2', 'Bob', sink2);
    });

    tearDown(() async => server.stop());

    test('only one FORCE_END_VOTE_START is sent even if called twice', () async {
      // Put the server into game state via direct API.
      // (Using handleMessageForTest to avoid WebSocket setup overhead.)
      // Since injectSessionForTest bypasses the game-start flow we drive
      // the server into inGame directly through the lobby WebSocket path.

      // Use a WS approach instead for a fully valid game state.
      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);
      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());
      await c1.next(WsMessageType.joinRoomAck);
      await c2.next(WsMessageType.joinRoomAck);
      c1.send(WsMessage(type: WsMessageType.setReady,
          payload: {'playerId': 'p1', 'isReady': true}));
      c2.send(WsMessage(type: WsMessageType.setReady,
          payload: {'playerId': 'p2', 'isReady': true}));
      server.startGame(packId: 'simple_card_battle');
      await c1.next(WsMessageType.playerView);

      final voteMessages = <WsMessage>[];
      final sub = c1.messages.listen((m) {
        if (m.type == WsMessageType.forceEndVoteStart) voteMessages.add(m);
      });

      server.startForceEndVote();
      server.startForceEndVote(); // No-op: vote already active.

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(voteMessages.length, equals(1),
          reason: 'Concurrent calls must not send duplicate FORCE_END_VOTE_START');

      await c1.close();
      await c2.close();
    });
  });

  // -------------------------------------------------------------------------
  // 7. Vote times out and auto-resolves with votes cast so far
  // -------------------------------------------------------------------------

  group('7. Vote auto-resolves after timeout', () {
    late GameServer server;
    late _WsClient c1;
    late _WsClient c2;

    setUp(() async {
      // Use a short timeout override so the test doesn't take 30 seconds.
      (server, c1, c2) = await _startGameWithTwoPlayers(
        voteTimeoutOverride: const Duration(milliseconds: 200),
      );
    });

    tearDown(() async {
      await c1.close();
      await c2.close();
      await server.stop();
    });

    test('timeout fires and broadcasts FORCE_END_VOTE_RESULT', () async {
      // Arm ALL listeners BEFORE starting the vote so we don't miss
      // the fast-firing (200ms) timeout in the full test suite.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final voteStartFuture2 = c2.next(WsMessageType.forceEndVoteStart);
      final resultFuture =
          c1.next(WsMessageType.forceEndVoteResult, timeout: const Duration(seconds: 3));

      server.startForceEndVote();
      await voteStartFuture1;
      await voteStartFuture2;

      // No votes cast — wait for the 200ms timeout to auto-resolve.
      final result = await resultFuture;

      // 0 agree out of 2 → not a majority.
      expect(result.payload['agreed'], isFalse);
      expect(result.payload['agreeCount'], equals(0));
      expect(result.payload['totalCount'], equals(2));
    });

    test('one agree before timeout → agreed=false (not majority)', () async {
      // Arm ALL listeners BEFORE starting vote.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final resultFuture =
          c1.next(WsMessageType.forceEndVoteResult, timeout: const Duration(seconds: 3));

      server.startForceEndVote();
      await voteStartFuture1;

      // Only p1 votes agree before timeout fires.
      c1.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p1', 'agree': true},
      ));

      final result = await resultFuture;

      // 1 agree out of 2 connected → 1 > 2/2 → 1 > 1 → false.
      expect(result.payload['agreed'], isFalse);
      expect(result.payload['agreeCount'], equals(1));
    });
  });

  // -------------------------------------------------------------------------
  // 8. GameResetEvent.forcedByVote is sent correctly
  // -------------------------------------------------------------------------

  group('8. GameResetEvent carries correct forcedByVote flag', () {
    test('forcedByVote=true when vote passes', () async {
      final events = <GameResetEvent>[];
      final eventPort = ReceivePort();
      eventPort.listen((e) {
        if (e is GameResetEvent) events.add(e);
      });

      final server = GameServer(
        gamePack: _NoOpGamePack(),
        eventPort: eventPort.sendPort,
        voteTimeoutOverride: const Duration(milliseconds: 200),
      );
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: _defaultState(),
      );

      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);
      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());
      await c1.next(WsMessageType.joinRoomAck);
      await c2.next(WsMessageType.joinRoomAck);
      c1.send(WsMessage(type: WsMessageType.setReady,
          payload: {'playerId': 'p1', 'isReady': true}));
      c2.send(WsMessage(type: WsMessageType.setReady,
          payload: {'playerId': 'p2', 'isReady': true}));
      server.startGame(packId: 'simple_card_battle');
      await c1.next(WsMessageType.playerView);

      // Arm ALL listeners BEFORE triggering vote to avoid missing fast messages.
      final voteStartFuture1 = c1.next(WsMessageType.forceEndVoteStart);
      final voteStartFuture2 = c2.next(WsMessageType.forceEndVoteStart);
      final resetFuture = c1.next(WsMessageType.gameReset);

      server.startForceEndVote();
      await voteStartFuture1;
      await voteStartFuture2;

      // Both agree.
      c1.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p1', 'agree': true},
      ));
      c2.send(WsMessage(
        type: WsMessageType.forceEndVote,
        payload: {'playerId': 'p2', 'agree': true},
      ));

      // Wait for GAME_RESET to confirm resolution.
      await resetFuture;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await server.stop();
      eventPort.close();

      final resetEvents =
          events.where((e) => e.forcedByVote).toList();
      expect(resetEvents.isNotEmpty, isTrue,
          reason: 'GameResetEvent must have forcedByVote=true when vote passes');

      await c1.close();
      await c2.close();
    });

    test('forcedByVote=false when resetGame() is called manually', () async {
      final events = <GameResetEvent>[];
      final eventPort = ReceivePort();
      eventPort.listen((e) {
        if (e is GameResetEvent) events.add(e);
      });

      final server = GameServer(
        gamePack: _NoOpGamePack(),
        eventPort: eventPort.sendPort,
      );
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: _defaultState(),
      );

      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);
      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());
      await c1.next(WsMessageType.joinRoomAck);
      await c2.next(WsMessageType.joinRoomAck);
      c1.send(WsMessage(type: WsMessageType.setReady,
          payload: {'playerId': 'p1', 'isReady': true}));
      c2.send(WsMessage(type: WsMessageType.setReady,
          payload: {'playerId': 'p2', 'isReady': true}));
      server.startGame(packId: 'simple_card_battle');
      await c1.next(WsMessageType.playerView);

      server.resetGame();
      await c1.next(WsMessageType.gameReset);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await server.stop();
      eventPort.close();

      final resetEvents =
          events.where((e) => !e.forcedByVote).toList();
      expect(resetEvents.isNotEmpty, isTrue,
          reason: 'GameResetEvent must have forcedByVote=false for manual reset');

      await c1.close();
      await c2.close();
    });
  });
} // end main
