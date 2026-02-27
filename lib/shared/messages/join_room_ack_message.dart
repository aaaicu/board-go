import 'ws_message.dart';

/// Server → Client acknowledgement of a JOIN request.
///
/// On success, [playerId] and [reconnectToken] are populated.
/// On failure, [errorCode] and [errorMessage] describe the rejection.
///
/// Error codes:
///   - 'ROOM_FULL'         — maximum player count reached.
///   - 'INVALID_TOKEN'     — the supplied reconnect token is unknown.
///   - 'NICKNAME_TAKEN'    — another connected player uses this nickname.
class JoinRoomAckMessage {
  final String? playerId;
  final String? reconnectToken;
  final bool success;
  final String? errorCode;
  final String? errorMessage;

  const JoinRoomAckMessage({
    this.playerId,
    this.reconnectToken,
    required this.success,
    this.errorCode,
    this.errorMessage,
  });

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.joinRoomAck,
        payload: {
          'success': success,
          if (playerId != null) 'playerId': playerId,
          if (reconnectToken != null) 'reconnectToken': reconnectToken,
          if (errorCode != null) 'errorCode': errorCode,
          if (errorMessage != null) 'errorMessage': errorMessage,
        },
      );

  factory JoinRoomAckMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.joinRoomAck);
    return JoinRoomAckMessage(
      success: msg.payload['success'] as bool,
      playerId: msg.payload['playerId'] as String?,
      reconnectToken: msg.payload['reconnectToken'] as String?,
      errorCode: msg.payload['errorCode'] as String?,
      errorMessage: msg.payload['errorMessage'] as String?,
    );
  }
}
