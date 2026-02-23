/// Immutable snapshot of the current game state.
class GameState {
  final String gameId;
  final int turn;
  final String activePlayerId;
  final Map<String, dynamic> data;

  const GameState({
    required this.gameId,
    required this.turn,
    required this.activePlayerId,
    required this.data,
  });

  GameState copyWith({
    String? gameId,
    int? turn,
    String? activePlayerId,
    Map<String, dynamic>? data,
  }) =>
      GameState(
        gameId: gameId ?? this.gameId,
        turn: turn ?? this.turn,
        activePlayerId: activePlayerId ?? this.activePlayerId,
        data: data ?? this.data,
      );

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        gameId: json['gameId'] as String,
        turn: json['turn'] as int,
        activePlayerId: json['activePlayerId'] as String,
        data: (json['data'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'turn': turn,
        'activePlayerId': activePlayerId,
        'data': data,
      };
}
