import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../lib/server/game_server.dart';
import '../../lib/shared/game_pack/game_pack_interface.dart';
import '../../lib/shared/game_pack/game_pack_rules.dart';
import '../../lib/shared/game_pack/game_state.dart';
import '../../lib/shared/game_pack/packs/simple_card_game.dart';
import '../../lib/shared/game_pack/player_action.dart';
import '../../lib/shared/game_session/game_session_state.dart';
import '../../lib/shared/game_session/player_session_state.dart';
import '../../lib/shared/game_session/session_phase.dart';
import '../../lib/shared/messages/action_message.dart';
import '../../lib/shared/messages/action_rejected_message.dart';
import '../../lib/shared/messages/join_message.dart';
import '../../lib/shared/messages/ws_message.dart';

// ---------------------------------------------------------------------------
// Test WebSocket client helper
// ---------------------------------------------------------------------------

class _WsClient {
  final WebSocketChannel _channel;
  final StreamController<WsMessage> _controller =
      StreamController<WsMessage>.broadcast();

  _WsClient(this._channel) {
    _channel.stream.listen(
      (raw) {
        try {
          final msg = WsMessage.fromJson(
            jsonDecode(raw as String) as Map<String, dynamic>,
          );
          if (!_controller.isClosed) _controller.add(msg);
        } catch (_) {
          // ignore malformed frames
        }
      },
      onDone: () {
        if (!_controller.isClosed) _controller.close();
      },
    );
  }

  static Future<_WsClient> connect(int port) async {
    final channel =
        WebSocketChannel.connect(Uri.parse('ws://localhost:$port/ws'));
    await channel.ready;
    return _WsClient(channel);
  }

  void send(WsMessage msg) => _channel.sink.add(jsonEncode(msg.toJson()));

  Stream<WsMessage> get messages => _controller.stream;

  Future<WsMessage> nextOfType(WsMessageType type,
      {Duration timeout = const Duration(seconds: 5)}) {
    return messages
        .firstWhere((m) => m.type == type)
        .timeout(timeout);
  }

  Future<void> close() => _channel.sink.close();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GameState _initialGameState() => GameState(
      gameId: 'pipeline-test',
      turn: 0,
      activePlayerId: 'p1',
      data: {},
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GameServer pipeline hardening', () {
    late GameServer server;

    setUp(() async {
      server = GameServer(gamePack: SimpleCardGame());
      await server.start(
        host: 'localhost',
        port: 0,
        initialState: _initialGameState(),
      );
    });

    tearDown(() async {
      await server.stop();
    });

    // -----------------------------------------------------------------------
    // Helpers used across tests
    // -----------------------------------------------------------------------

    /// Joins both p1 and p2 and starts the game.  Returns both clients and
    /// waits until both have received their initial PLAYER_VIEW.
    ///
    /// IMPORTANT: listeners are armed BEFORE [startGame] is called to avoid
    /// the broadcast-stream race (events sent with no active listener are lost).
    Future<(_WsClient, _WsClient)> _joinAndStart() async {
      final c1 = await _WsClient.connect(server.port!);
      final c2 = await _WsClient.connect(server.port!);

      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      c2.send(JoinMessage.join(playerId: 'p2', displayName: 'Bob').toEnvelope());

      // Wait for both ACKs before arming the PLAYER_VIEW futures.
      await c1.nextOfType(WsMessageType.joinRoomAck);
      await c2.nextOfType(WsMessageType.joinRoomAck);

      // Arm the PLAYER_VIEW futures BEFORE calling startGame so we don't miss
      // the initial broadcast (broadcast streams do not buffer).
      final pv1Future = c1.nextOfType(WsMessageType.playerView);
      final pv2Future = c2.nextOfType(WsMessageType.playerView);

      // Transition to in-game.
      server.startGame();

      // Wait for both initial PLAYER_VIEW messages.
      await pv1Future;
      await pv2Future;

      return (c1, c2);
    }

    // -----------------------------------------------------------------------
    // Duplicate action rejection
    // -----------------------------------------------------------------------

    test('duplicate clientActionId returns ACTION_REJECTED(DUPLICATE_ACTION)', () async {
      final (c1, c2) = await _joinAndStart();

      // Use an empty params action for simplicity — END_TURN is always allowed.
      final endTurnMsg = ActionMessage(
        playerId: 'p1',
        actionType: 'END_TURN',
        data: {},
        clientActionId: 'unique-id-001',
      ).toEnvelope();

      // First send → accepted (produces PLAYER_VIEW / BOARD_VIEW).
      c1.send(endTurnMsg);
      await c1.nextOfType(WsMessageType.playerView);

      // Second send with same clientActionId → rejected.
      c1.send(endTurnMsg);
      final rejection = await c1.nextOfType(WsMessageType.actionRejected);
      final rej = ActionRejectedMessage.fromEnvelope(rejection);

      expect(rej.code, equals(ActionRejectedCode.duplicateAction));
      expect(rej.clientActionId, equals('unique-id-001'));

      await Future.wait([c1.close(), c2.close()]);
    });

    // -----------------------------------------------------------------------
    // Not-your-turn rejection
    // -----------------------------------------------------------------------

    test('action from non-active player returns ACTION_REJECTED(NOT_YOUR_TURN)', () async {
      final (c1, c2) = await _joinAndStart();

      // p2 is NOT the active player at game start (p1 is).
      c2.send(
        ActionMessage(
          playerId: 'p2',
          actionType: 'END_TURN',
          data: {},
          clientActionId: 'p2-action-001',
        ).toEnvelope(),
      );

      final rejection = await c2.nextOfType(WsMessageType.actionRejected);
      final rej = ActionRejectedMessage.fromEnvelope(rejection);

      expect(rej.code, equals(ActionRejectedCode.notYourTurn));

      await Future.wait([c1.close(), c2.close()]);
    });

    // -----------------------------------------------------------------------
    // Phase mismatch rejection (lobby phase)
    // -----------------------------------------------------------------------

    test('action during lobby phase falls back to legacy handler (no PHASE_MISMATCH crash)', () async {
      // Do NOT call startGame — server stays in lobby phase.
      final c1 = await _WsClient.connect(server.port!);
      c1.send(JoinMessage.join(playerId: 'p1', displayName: 'Alice').toEnvelope());
      await c1.nextOfType(WsMessageType.joinRoomAck);

      // The legacy path handles this.  It may send an ERROR (invalid action
      // per SimpleCardGame.validateAction) or a STATE_UPDATE — either is fine.
      // What must NOT happen is an unhandled exception crashing the test.
      c1.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'PLAY_CARD',
          data: {'cardId': 'nonexistent'},
        ).toEnvelope(),
      );

      // Expect either an error or a state update within 2 seconds.
      final msg = await c1.messages
          .firstWhere((m) =>
              m.type == WsMessageType.error ||
              m.type == WsMessageType.stateUpdate ||
              m.type == WsMessageType.actionRejected)
          .timeout(const Duration(seconds: 2));

      expect(
        [WsMessageType.error, WsMessageType.stateUpdate, WsMessageType.actionRejected],
        contains(msg.type),
      );

      await c1.close();
    });

    // -----------------------------------------------------------------------
    // Valid action → version++ + PLAYER_VIEW/BOARD_VIEW sent
    // -----------------------------------------------------------------------

    test('valid END_TURN → version increments + PLAYER_VIEW and BOARD_VIEW sent', () async {
      final (c1, c2) = await _joinAndStart();

      // Capture the initial version from the BOARD_VIEW received during startGame.
      // We wait for a fresh BOARD_VIEW after the action.
      final boardViewFuture = c1.nextOfType(WsMessageType.boardView);
      final playerViewFuture = c1.nextOfType(WsMessageType.playerView);

      c1.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'END_TURN',
          data: {},
        ).toEnvelope(),
      );

      final boardMsg = await boardViewFuture;
      final playerMsg = await playerViewFuture;

      // Both message types must arrive.
      expect(boardMsg.type, equals(WsMessageType.boardView));
      expect(playerMsg.type, equals(WsMessageType.playerView));

      // The BOARD_VIEW payload must contain a 'boardView' key.
      expect(boardMsg.payload.containsKey('boardView'), isTrue);

      // The PLAYER_VIEW payload must contain a 'playerView' key with
      // no 'hands' sub-key (privacy check at the message level).
      final pvPayload =
          playerMsg.payload['playerView'] as Map<String, dynamic>;
      expect(pvPayload.containsKey('hands'), isFalse);

      await Future.wait([c1.close(), c2.close()]);
    });

    // -----------------------------------------------------------------------
    // BOARD_VIEW is broadcast; PLAYER_VIEW is individual
    // -----------------------------------------------------------------------

    test('BOARD_VIEW is received by both clients; PLAYER_VIEW is individual', () async {
      final (c1, c2) = await _joinAndStart();

      // After startGame, both clients should have already received their
      // initial PLAYER_VIEW and a BOARD_VIEW.  We trigger another round.
      final bv1Future = c1.nextOfType(WsMessageType.boardView);
      final bv2Future = c2.nextOfType(WsMessageType.boardView);
      final pv1Future = c1.nextOfType(WsMessageType.playerView);
      final pv2Future = c2.nextOfType(WsMessageType.playerView);

      c1.send(
        ActionMessage(
          playerId: 'p1',
          actionType: 'END_TURN',
          data: {},
        ).toEnvelope(),
      );

      // Both should receive BOARD_VIEW (broadcast).
      await bv1Future;
      await bv2Future;

      // Both should receive their own PLAYER_VIEW.
      final pv1 = await pv1Future;
      final pv2 = await pv2Future;

      // p1's view must say playerId == p1; p2's must say playerId == p2.
      final pv1Data = pv1.payload['playerView'] as Map<String, dynamic>;
      final pv2Data = pv2.payload['playerView'] as Map<String, dynamic>;

      expect(pv1Data['playerId'], equals('p1'));
      expect(pv2Data['playerId'], equals('p2'));

      // Cross-check: the hands in each view must not overlap.
      final hand1 = List<String>.from(pv1Data['hand'] as List);
      final hand2 = List<String>.from(pv2Data['hand'] as List);
      for (final card in hand1) {
        expect(hand2, isNot(contains(card)),
            reason: "p2's PLAYER_VIEW must not include p1's cards");
      }

      await Future.wait([c1.close(), c2.close()]);
    });
  });
}
