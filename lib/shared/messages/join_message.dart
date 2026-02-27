import 'ws_message.dart';

/// Player join or leave notification.
///
/// [reconnectToken] is optional. When provided on a JOIN, the server
/// will attempt to restore the player's existing session instead of
/// creating a new one.
class JoinMessage {
  final String playerId;
  final String? displayName;
  final bool isJoin;

  /// Optional reconnect token sent by a returning client.
  final String? reconnectToken;

  const JoinMessage._({
    required this.playerId,
    this.displayName,
    required this.isJoin,
    this.reconnectToken,
  });

  factory JoinMessage.join({
    required String playerId,
    required String displayName,
    String? reconnectToken,
  }) =>
      JoinMessage._(
        playerId: playerId,
        displayName: displayName,
        isJoin: true,
        reconnectToken: reconnectToken,
      );

  factory JoinMessage.leave({required String playerId}) =>
      JoinMessage._(playerId: playerId, isJoin: false);

  WsMessage toEnvelope() => WsMessage(
        type: isJoin ? WsMessageType.join : WsMessageType.leave,
        payload: {
          'playerId': playerId,
          if (displayName != null) 'displayName': displayName,
          'event': isJoin ? 'join' : 'leave',
          if (reconnectToken != null) 'reconnectToken': reconnectToken,
        },
      );

  factory JoinMessage.fromEnvelope(WsMessage msg) {
    final isJoin = msg.type == WsMessageType.join;
    return JoinMessage._(
      playerId: msg.payload['playerId'] as String,
      displayName: msg.payload['displayName'] as String?,
      isJoin: isJoin,
      reconnectToken: msg.payload['reconnectToken'] as String?,
    );
  }
}
