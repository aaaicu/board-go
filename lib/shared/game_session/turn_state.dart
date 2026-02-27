import 'turn_step.dart';

/// Immutable snapshot of the current turn within a game round.
///
/// [round] is 1-based. [turnIndex] is the index into [GameSessionState.playerOrder]
/// identifying whose turn it is. [actionCountThisTurn] tracks how many actions
/// the active player has taken this turn (for rules that limit per-turn actions).
class TurnState {
  final int round;
  final int turnIndex;
  final String activePlayerId;
  final TurnStep step;
  final int actionCountThisTurn;

  const TurnState({
    required this.round,
    required this.turnIndex,
    required this.activePlayerId,
    required this.step,
    required this.actionCountThisTurn,
  });

  TurnState copyWith({
    int? round,
    int? turnIndex,
    String? activePlayerId,
    TurnStep? step,
    int? actionCountThisTurn,
  }) =>
      TurnState(
        round: round ?? this.round,
        turnIndex: turnIndex ?? this.turnIndex,
        activePlayerId: activePlayerId ?? this.activePlayerId,
        step: step ?? this.step,
        actionCountThisTurn: actionCountThisTurn ?? this.actionCountThisTurn,
      );

  factory TurnState.fromJson(Map<String, dynamic> json) => TurnState(
        round: json['round'] as int,
        turnIndex: json['turnIndex'] as int,
        activePlayerId: json['activePlayerId'] as String,
        step: TurnStep.fromJson(json['step'] as String),
        actionCountThisTurn: json['actionCountThisTurn'] as int,
      );

  Map<String, dynamic> toJson() => {
        'round': round,
        'turnIndex': turnIndex,
        'activePlayerId': activePlayerId,
        'step': step.toJson(),
        'actionCountThisTurn': actionCountThisTurn,
      };
}
