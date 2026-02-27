import 'ws_message.dart';

/// A player action sent from a GameNode to the GameBoard.
///
/// [clientActionId] is an optional client-generated idempotency key.
/// The server echoes it back in the response so the client can correlate
/// acknowledgements with optimistic local updates.
class ActionMessage {
  final String playerId;
  final String actionType;
  final Map<String, dynamic> data;

  /// Optional idempotency key set by the client (nullable, backward-compat).
  final String? clientActionId;

  const ActionMessage({
    required this.playerId,
    required this.actionType,
    required this.data,
    this.clientActionId,
  });

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.action,
        payload: {
          'playerId': playerId,
          'actionType': actionType,
          'data': data,
          if (clientActionId != null) 'clientActionId': clientActionId,
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
      clientActionId: msg.payload['clientActionId'] as String?,
    );
  }
}
