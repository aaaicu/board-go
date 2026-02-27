import 'ws_message.dart';

/// Client → Server message to toggle the player's ready state.
class SetReadyMessage {
  final String playerId;
  final bool isReady;

  const SetReadyMessage({required this.playerId, required this.isReady});

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.setReady,
        payload: {
          'playerId': playerId,
          'isReady': isReady,
        },
      );

  factory SetReadyMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.setReady);
    return SetReadyMessage(
      playerId: msg.payload['playerId'] as String,
      isReady: msg.payload['isReady'] as bool,
    );
  }
}
