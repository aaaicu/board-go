/// Immutable per-player state within a session.
///
/// [reconnectToken] is a UUID v4 that uniquely identifies the player's
/// "seat" across disconnects. It is serialised in JSON so the client can
/// store it and use it to reclaim the same seat after a reconnect.
///
/// [connectionId] is an internal server concept (the opaque sink key) and is
/// intentionally excluded from serialisation.
class PlayerSessionState {
  final String playerId;
  final String nickname;
  final bool isConnected;
  final bool isReady;
  final String reconnectToken;

  const PlayerSessionState({
    required this.playerId,
    required this.nickname,
    required this.isConnected,
    required this.isReady,
    required this.reconnectToken,
  });

  PlayerSessionState copyWith({
    String? playerId,
    String? nickname,
    bool? isConnected,
    bool? isReady,
    String? reconnectToken,
  }) =>
      PlayerSessionState(
        playerId: playerId ?? this.playerId,
        nickname: nickname ?? this.nickname,
        isConnected: isConnected ?? this.isConnected,
        isReady: isReady ?? this.isReady,
        reconnectToken: reconnectToken ?? this.reconnectToken,
      );

  factory PlayerSessionState.fromJson(Map<String, dynamic> json) =>
      PlayerSessionState(
        playerId: json['playerId'] as String,
        nickname: json['nickname'] as String,
        isConnected: json['isConnected'] as bool,
        isReady: json['isReady'] as bool,
        reconnectToken: json['reconnectToken'] as String,
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'nickname': nickname,
        'isConnected': isConnected,
        'isReady': isReady,
        'reconnectToken': reconnectToken,
      };
}
