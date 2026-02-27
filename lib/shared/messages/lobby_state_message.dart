import 'ws_message.dart';

/// Per-player summary included in a LOBBY_STATE broadcast.
class LobbyStatePlayerInfo {
  final String playerId;
  final String nickname;
  final bool isReady;
  final bool isConnected;

  const LobbyStatePlayerInfo({
    required this.playerId,
    required this.nickname,
    required this.isReady,
    required this.isConnected,
  });

  factory LobbyStatePlayerInfo.fromJson(Map<String, dynamic> json) =>
      LobbyStatePlayerInfo(
        playerId: json['playerId'] as String,
        nickname: json['nickname'] as String,
        isReady: json['isReady'] as bool,
        isConnected: json['isConnected'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'nickname': nickname,
        'isReady': isReady,
        'isConnected': isConnected,
      };
}

/// Server → all clients broadcast describing the current lobby state.
///
/// [canStart] is true when at least one connected player is ready and all
/// connected players have set their ready flag to true.
class LobbyStateMessage {
  final List<LobbyStatePlayerInfo> players;
  final bool canStart;

  const LobbyStateMessage({
    required this.players,
    required this.canStart,
  });

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.lobbyState,
        payload: {
          'players': players.map((p) => p.toJson()).toList(),
          'canStart': canStart,
        },
      );

  factory LobbyStateMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.lobbyState);
    final rawPlayers = msg.payload['players'] as List<dynamic>;
    return LobbyStateMessage(
      players: rawPlayers
          .map((e) => LobbyStatePlayerInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      canStart: msg.payload['canStart'] as bool,
    );
  }
}
