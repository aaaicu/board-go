/// Lifecycle phases of a game session.
enum SessionPhase {
  lobby,
  inGame,
  roundEnd,
  finished;

  String toJson() => switch (this) {
        SessionPhase.lobby => 'lobby',
        SessionPhase.inGame => 'inGame',
        SessionPhase.roundEnd => 'roundEnd',
        SessionPhase.finished => 'finished',
      };

  static SessionPhase fromJson(String value) => switch (value) {
        'lobby' => SessionPhase.lobby,
        'inGame' => SessionPhase.inGame,
        'roundEnd' => SessionPhase.roundEnd,
        'finished' => SessionPhase.finished,
        _ => throw FormatException('Unknown SessionPhase: $value'),
      };
}
