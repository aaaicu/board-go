import 'ws_message.dart';

/// Client → server message to change a player's displayed nickname while a
/// session is already in progress.
///
/// The server updates the corresponding [SessionManager] entry and rebroadcasts
/// [LobbyStateMessage] (or the equivalent in-game views) so every client sees
/// the new name.
class RenamePlayerMessage {
  final String playerId;
  final String displayName;

  const RenamePlayerMessage({
    required this.playerId,
    required this.displayName,
  });

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.renamePlayer,
        payload: {
          'playerId': playerId,
          'displayName': displayName,
        },
      );

  factory RenamePlayerMessage.fromEnvelope(WsMessage msg) {
    return RenamePlayerMessage(
      playerId: msg.payload['playerId'] as String,
      displayName: msg.payload['displayName'] as String,
    );
  }
}
