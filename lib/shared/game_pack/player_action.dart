/// An action submitted by a player.
class PlayerAction {
  final String playerId;
  final String type;
  final Map<String, dynamic> data;

  const PlayerAction({
    required this.playerId,
    required this.type,
    required this.data,
  });

  factory PlayerAction.fromJson(Map<String, dynamic> json) => PlayerAction(
        playerId: json['playerId'] as String,
        type: json['type'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'type': type,
        'data': data,
      };
}
