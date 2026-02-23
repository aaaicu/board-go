import 'ws_message.dart';

/// A full game-state broadcast sent from the GameBoard to all GameNodes.
class StateUpdateMessage {
  final Map<String, dynamic> state;
  final String? triggeredBy;

  const StateUpdateMessage({required this.state, this.triggeredBy});

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.stateUpdate,
        payload: {
          'state': state,
          if (triggeredBy != null) 'triggeredBy': triggeredBy,
        },
      );

  factory StateUpdateMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.stateUpdate);
    return StateUpdateMessage(
      state: (msg.payload['state'] as Map<String, dynamic>?) ?? {},
      triggeredBy: msg.payload['triggeredBy'] as String?,
    );
  }
}
