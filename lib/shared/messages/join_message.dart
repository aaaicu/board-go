import 'ws_message.dart';

/// Player join or leave notification.
class JoinMessage {
  final String playerId;
  final String? displayName;
  final bool isJoin;

  const JoinMessage._({
    required this.playerId,
    this.displayName,
    required this.isJoin,
  });

  factory JoinMessage.join({
    required String playerId,
    required String displayName,
  }) =>
      JoinMessage._(playerId: playerId, displayName: displayName, isJoin: true);

  factory JoinMessage.leave({required String playerId}) =>
      JoinMessage._(playerId: playerId, isJoin: false);

  WsMessage toEnvelope() => WsMessage(
        type: isJoin ? WsMessageType.join : WsMessageType.leave,
        payload: {
          'playerId': playerId,
          if (displayName != null) 'displayName': displayName,
          'event': isJoin ? 'join' : 'leave',
        },
      );

  factory JoinMessage.fromEnvelope(WsMessage msg) {
    final isJoin = msg.type == WsMessageType.join;
    return JoinMessage._(
      playerId: msg.payload['playerId'] as String,
      displayName: msg.payload['displayName'] as String?,
      isJoin: isJoin,
    );
  }
}
