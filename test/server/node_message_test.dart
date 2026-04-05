import 'dart:convert';

import 'package:test/test.dart';

import '../../lib/server/game_server.dart';
import '../../lib/server/session_manager.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_pack_rules.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/packs/simple_card_game_emotes.dart';
import '../../lib/shared/game_pack/packs/simple_card_game_rules.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/game_pack/views/allowed_action.dart';
import '../../lib/shared/game_pack/views/board_view.dart';
import '../../lib/shared/game_pack/views/player_view.dart';
import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';
import '../../lib/shared/messages/node_message.dart';
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

  /// Decodes all received raw strings as [WsMessage] objects.
  List<WsMessage> get messages => sent
      .map((s) =>
          WsMessage.fromJson(jsonDecode(s) as Map<String, dynamic>))
      .toList();

  /// Filters to NODE_MESSAGE envelopes and decodes them.
  List<NodeMessage> get nodeMessages => messages
      .where((m) => m.type == WsMessageType.nodeMessage)
      .map(NodeMessage.fromEnvelope)
      .toList();
}

/// A minimal [GameSessionState] useful as a placeholder in rule-hook tests.
GameSessionState _emptyLobbyState() => GameSessionState(
      sessionId: 'test-session',
      phase: SessionPhase.lobby,
      players: const {},
      playerOrder: const [],
      version: 0,
      log: const [],
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('NodeMessage serialisation', () {
    test('round-trips through toJson / fromJson', () {
      const original = NodeMessage(
        fromPlayerId: 'playerA',
        toPlayerId: 'playerB',
        type: 'EMOTE',
        payload: {'emoji': '👍'},
      );

      final decoded = NodeMessage.fromJson(original.toJson());
      expect(decoded.fromPlayerId, 'playerA');
      expect(decoded.toPlayerId, 'playerB');
      expect(decoded.type, 'EMOTE');
      expect(decoded.payload['emoji'], '👍');
    });

    test('omits toPlayerId key when null (broadcast)', () {
      const msg = NodeMessage(fromPlayerId: 'p1', type: 'EMOTE');
      final json = msg.toJson();
      expect(json.containsKey('toPlayerId'), isFalse);
    });

    test('toEnvelope / fromEnvelope preserves all fields', () {
      const original = NodeMessage(
        fromPlayerId: 'p1',
        toPlayerId: 'p2',
        type: 'EMOTE',
        payload: {'emoji': '🎉'},
      );
      final decoded = NodeMessage.fromEnvelope(original.toEnvelope());
      expect(decoded.fromPlayerId, original.fromPlayerId);
      expect(decoded.toPlayerId, original.toPlayerId);
      expect(decoded.type, original.type);
      expect(decoded.payload, original.payload);
    });
  });

  group('GamePackRules.onNodeMessage — default pass-through', () {
    test('returns the message unchanged', () {
      final rules = _PassThroughRules();
      const msg = NodeMessage(fromPlayerId: 'p1', type: 'ANYTHING');
      final result = rules.onNodeMessage(msg, _emptyLobbyState());
      expect(result, same(msg));
    });
  });

  group('SimpleCardGameRules.onNodeMessage', () {
    const rules = SimpleCardGameRules();

    test('passes valid EMOTE with thumbsUp emoji', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.emote,
        payload: {'emoji': SimpleCardGameEmote.thumbsUp},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), same(msg));
    });

    test('passes all supported emoji values', () {
      for (final emoji in SimpleCardGameEmote.all) {
        final msg = NodeMessage(
          fromPlayerId: 'p1',
          type: SimpleCardGameEmote.emote,
          payload: {'emoji': emoji},
        );
        expect(
          rules.onNodeMessage(msg, _emptyLobbyState()),
          isNotNull,
          reason: 'emoji "$emoji" should pass the filter',
        );
      }
    });

    test('blocks EMOTE with unknown emoji', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.emote,
        payload: {'emoji': '\u{1F480}'}, // 💀 — not in allowlist
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNull);
    });

    test('blocks EMOTE with missing emoji key in payload', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.emote,
        payload: {},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNull);
    });

    test('passes valid CHAT message within 20 chars', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.chat,
        payload: {'text': 'hello'},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), same(msg));
    });

    test('passes CHAT message at exactly 20 chars', () {
      final msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.chat,
        payload: {'text': 'a' * 20},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNotNull);
    });

    test('blocks CHAT message exceeding 20 chars', () {
      final msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.chat,
        payload: {'text': 'a' * 21},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNull);
    });

    test('blocks CHAT message with empty text', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.chat,
        payload: {'text': ''},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNull);
    });

    test('blocks CHAT message with missing text key', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: SimpleCardGameEmote.chat,
        payload: {},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNull);
    });

    test('blocks unknown message type', () {
      const msg = NodeMessage(
        fromPlayerId: 'p1',
        type: 'UNKNOWN_TYPE',
        payload: {'text': 'hello'},
      );
      expect(rules.onNodeMessage(msg, _emptyLobbyState()), isNull);
    });
  });

  group('GameServer node message routing', () {
    late GameServer server;
    late _FakeSink sinkA;
    late _FakeSink sinkB;

    setUp(() async {
      server = GameServer(
        gamePack: _NoOpGamePack(),
        rulesFactoryMap: {
          'simple_card_battle': () => const SimpleCardGameRules(),
        },
      );
      await server.start(
        initialState: GameState(
          gameId: 'test',
          turn: 0,
          activePlayerId: 'playerA',
          data: const {},
        ),
      );
      sinkA = _FakeSink();
      sinkB = _FakeSink();
      server.injectSessionForTest('playerA', 'Alice', sinkA);
      server.injectSessionForTest('playerB', 'Bob', sinkB);
    });

    tearDown(() async => server.stop());

    test('unregistered sender is silently dropped', () {
      server.handleMessageForTest(
        jsonEncode(NodeMessage(
          fromPlayerId: 'ghost',
          type: SimpleCardGameEmote.emote,
          payload: {'emoji': SimpleCardGameEmote.thumbsUp},
        ).toEnvelope().toJson()),
        sinkA,
      );

      expect(sinkA.nodeMessages, isEmpty);
      expect(sinkB.nodeMessages, isEmpty);
    });

    test('broadcast (toPlayerId null) delivers to all connected players', () {
      server.handleMessageForTest(
        jsonEncode(NodeMessage(
          fromPlayerId: 'playerA',
          type: SimpleCardGameEmote.emote,
          payload: {'emoji': SimpleCardGameEmote.celebrate},
        ).toEnvelope().toJson()),
        sinkA,
      );

      expect(sinkA.nodeMessages, hasLength(1));
      expect(sinkB.nodeMessages, hasLength(1));
      expect(
        sinkA.nodeMessages.first.payload['emoji'],
        SimpleCardGameEmote.celebrate,
      );
    });

    test('unicast (toPlayerId set) delivers only to the target player', () {
      server.handleMessageForTest(
        jsonEncode(NodeMessage(
          fromPlayerId: 'playerA',
          toPlayerId: 'playerB',
          type: SimpleCardGameEmote.emote,
          payload: {'emoji': SimpleCardGameEmote.laugh},
        ).toEnvelope().toJson()),
        sinkA,
      );

      // Sender does NOT receive a unicast directed at someone else.
      expect(sinkA.nodeMessages, isEmpty);
      expect(sinkB.nodeMessages, hasLength(1));
      expect(
        sinkB.nodeMessages.first.payload['emoji'],
        SimpleCardGameEmote.laugh,
      );
    });

    test('CHAT within 20 chars is routed to all players', () {
      server.handleMessageForTest(
        jsonEncode(NodeMessage(
          fromPlayerId: 'playerA',
          type: SimpleCardGameEmote.chat,
          payload: {'text': 'hello'},
        ).toEnvelope().toJson()),
        sinkA,
      );

      expect(sinkA.nodeMessages, hasLength(1));
      expect(sinkB.nodeMessages, hasLength(1));
      expect(sinkA.nodeMessages.first.payload['text'], 'hello');
    });

    test('CHAT exceeding 20 chars is blocked by GamePack', () {
      server.handleMessageForTest(
        jsonEncode(NodeMessage(
          fromPlayerId: 'playerA',
          type: SimpleCardGameEmote.chat,
          payload: {'text': 'a' * 21},
        ).toEnvelope().toJson()),
        sinkA,
      );

      expect(sinkA.nodeMessages, isEmpty);
      expect(sinkB.nodeMessages, isEmpty);
    });

    test('GamePack returning null blocks unknown message types', () {
      server.handleMessageForTest(
        jsonEncode(NodeMessage(
          fromPlayerId: 'playerA',
          type: 'UNKNOWN_TYPE',
          payload: {'text': 'should be blocked'},
        ).toEnvelope().toJson()),
        sinkA,
      );

      expect(sinkA.nodeMessages, isEmpty);
      expect(sinkB.nodeMessages, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal GamePackRules stub — leaves onNodeMessage unoverridden to test the
// default pass-through behaviour defined in the abstract class.
// ---------------------------------------------------------------------------

class _PassThroughRules extends GamePackRules {
  @override
  String get packId => 'pass-through';

  @override
  int get minPlayers => 1;

  @override
  int get maxPlayers => 8;

  @override
  GameSessionState createInitialGameState(GameSessionState s) => s;

  @override
  List<AllowedAction> getAllowedActions(
          GameSessionState s, String playerId) =>
      const [];

  @override
  GameSessionState applyAction(
          GameSessionState s, String p, PlayerAction a) =>
      s;

  @override
  ({bool ended, List<String> winnerIds}) checkGameEnd(GameSessionState s) =>
      (ended: false, winnerIds: const []);

  @override
  BoardView buildBoardView(GameSessionState s) => BoardView(
        phase: s.phase,
        scores: const {},
        turnState: null,
        deckRemaining: 0,
        discardPile: const [],
        recentLog: const [],
        version: 0,
      );

  @override
  PlayerView buildPlayerView(GameSessionState s, String playerId) =>
      PlayerView(
        phase: s.phase,
        playerId: playerId,
        hand: const [],
        scores: const {},
        turnState: null,
        allowedActions: const [],
        version: 0,
      );

  // onNodeMessage NOT overridden — inherits the default pass-through from GamePackRules.
}
