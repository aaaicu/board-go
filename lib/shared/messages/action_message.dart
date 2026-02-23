import 'ws_message.dart';

/// A player action sent from a GameNode to the GameBoard.
class ActionMessage {
  final String playerId;
  final String actionType;
  final Map<String, dynamic> data;

  const ActionMessage({
    required this.playerId,
    required this.actionType,
    required this.data,
  });

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.action,
        payload: {
          'playerId': playerId,
          'actionType': actionType,
          'data': data,
        },
      );

  factory ActionMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.action);
    return ActionMessage(
      playerId: msg.payload['playerId'] as String,
      actionType: msg.payload['actionType'] as String,
      data: Map<String, dynamic>.from(
        (msg.payload['data'] as Map?) ?? {},
      ),
    );
  }
}
