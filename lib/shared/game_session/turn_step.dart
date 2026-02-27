/// The current step within a player's turn.
enum TurnStep {
  start,
  main,
  end;

  String toJson() => name.toUpperCase();

  static TurnStep fromJson(String value) => switch (value) {
        'START' => TurnStep.start,
        'MAIN' => TurnStep.main,
        'END' => TurnStep.end,
        _ => throw FormatException('Unknown TurnStep: $value'),
      };
}
