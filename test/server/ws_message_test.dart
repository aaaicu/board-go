import 'dart:convert';

import 'package:test/test.dart';

import '../../lib/shared/messages/ws_message.dart';
import '../../lib/shared/messages/action_message.dart';
import '../../lib/shared/messages/state_update_message.dart';
import '../../lib/shared/messages/join_message.dart';

void main() {
  group('WsMessage serialization', () {
    test('round-trips through JSON', () {
      final msg = WsMessage(
        type: WsMessageType.action,
        payload: {'key': 'value'},
        timestamp: 1708612345678,
      );
      final json = msg.toJson();
      final decoded = WsMessage.fromJson(json);

      expect(decoded.type, equals(WsMessageType.action));
      expect(decoded.payload, equals({'key': 'value'}));
      expect(decoded.timestamp, equals(1708612345678));
    });

    test('serializes to JSON string and back', () {
      final msg = WsMessage(
        type: WsMessageType.stateUpdate,
        payload: {'score': 42},
      );
      final jsonStr = jsonEncode(msg.toJson());
      final decoded = WsMessage.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      expect(decoded.type, equals(WsMessageType.stateUpdate));
      expect(decoded.payload['score'], equals(42));
    });

    test('all message types round-trip', () {
      for (final type in WsMessageType.values) {
        final msg = WsMessage(type: type, payload: {});
        final decoded = WsMessage.fromJson(msg.toJson());
        expect(decoded.type, equals(type));
      }
    });

    test('unknown type throws FormatException', () {
      expect(
        () => WsMessage.fromJson({'type': 'UNKNOWN', 'payload': {}}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ActionMessage', () {
    test('wraps action in WsMessage envelope', () {
      final msg = ActionMessage(
        playerId: 'player-1',
        actionType: 'PLAY_CARD',
        data: {'cardId': 'ace-of-spades'},
      );
      final envelope = msg.toEnvelope();

      expect(envelope.type, equals(WsMessageType.action));
      expect(envelope.payload['playerId'], equals('player-1'));
      expect(envelope.payload['actionType'], equals('PLAY_CARD'));
      expect(envelope.payload['data']['cardId'], equals('ace-of-spades'));
    });

    test('parses from WsMessage envelope', () {
      final envelope = WsMessage(
        type: WsMessageType.action,
        payload: {
          'playerId': 'player-2',
          'actionType': 'DRAW_CARD',
          'data': {},
        },
      );
      final action = ActionMessage.fromEnvelope(envelope);

      expect(action.playerId, equals('player-2'));
      expect(action.actionType, equals('DRAW_CARD'));
    });
  });

  group('StateUpdateMessage', () {
    test('wraps state in WsMessage envelope', () {
      final msg = StateUpdateMessage(
        state: {'turn': 1, 'activePlayer': 'player-1'},
        triggeredBy: 'player-1',
      );
      final envelope = msg.toEnvelope();

      expect(envelope.type, equals(WsMessageType.stateUpdate));
      expect(envelope.payload['state']['turn'], equals(1));
      expect(envelope.payload['triggeredBy'], equals('player-1'));
    });

    test('parses from WsMessage envelope', () {
      final envelope = WsMessage(
        type: WsMessageType.stateUpdate,
        payload: {
          'state': {'turn': 2},
          'triggeredBy': 'player-2',
        },
      );
      final update = StateUpdateMessage.fromEnvelope(envelope);
      expect(update.state['turn'], equals(2));
      expect(update.triggeredBy, equals('player-2'));
    });
  });

  group('JoinMessage', () {
    test('join wraps in WsMessage envelope', () {
      final msg = JoinMessage.join(playerId: 'player-3', displayName: 'Alice');
      final envelope = msg.toEnvelope();

      expect(envelope.type, equals(WsMessageType.join));
      expect(envelope.payload['playerId'], equals('player-3'));
      expect(envelope.payload['displayName'], equals('Alice'));
      expect(envelope.payload['event'], equals('join'));
    });

    test('leave wraps in WsMessage envelope', () {
      final msg = JoinMessage.leave(playerId: 'player-3');
      final envelope = msg.toEnvelope();

      expect(envelope.type, equals(WsMessageType.leave));
      expect(envelope.payload['event'], equals('leave'));
    });
  });
}
