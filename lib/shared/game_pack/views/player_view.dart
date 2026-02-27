import '../../game_session/session_phase.dart';
import '../../game_session/turn_state.dart';
import 'allowed_action.dart';

/// The private view sent exclusively to one player's device.
///
/// Security invariant: [hand] contains ONLY the cards belonging to [playerId].
/// The server must never include another player's cards in this object.
class PlayerView {
  final SessionPhase phase;

  /// The player who owns this view.
  final String playerId;

  /// This player's private hand (card ID strings). Never exposed to others.
  final List<String> hand;

  /// Public scores for all players.
  final Map<String, int> scores;

  /// Null while in lobby phase.
  final TurnState? turnState;

  /// Actions this player is currently permitted to take.
  /// Empty when it is not this player's turn.
  final List<AllowedAction> allowedActions;

  /// Monotonically increasing version counter mirroring [GameSessionState.version].
  final int version;

  const PlayerView({
    required this.phase,
    required this.playerId,
    required this.hand,
    required this.scores,
    required this.turnState,
    required this.allowedActions,
    required this.version,
  });

  PlayerView copyWith({
    SessionPhase? phase,
    String? playerId,
    List<String>? hand,
    Map<String, int>? scores,
    Object? turnState = _kUnset,
    List<AllowedAction>? allowedActions,
    int? version,
  }) =>
      PlayerView(
        phase: phase ?? this.phase,
        playerId: playerId ?? this.playerId,
        hand: hand ?? this.hand,
        scores: scores ?? this.scores,
        turnState: identical(turnState, _kUnset)
            ? this.turnState
            : turnState as TurnState?,
        allowedActions: allowedActions ?? this.allowedActions,
        version: version ?? this.version,
      );

  factory PlayerView.fromJson(Map<String, dynamic> json) {
    final rawTurnState = json['turnState'] as Map<String, dynamic>?;
    final rawScores = (json['scores'] as Map<String, dynamic>?) ?? {};
    final rawActions = (json['allowedActions'] as List<dynamic>?) ?? [];

    return PlayerView(
      phase: SessionPhase.fromJson(json['phase'] as String),
      playerId: json['playerId'] as String,
      hand: List<String>.from((json['hand'] as List<dynamic>?) ?? []),
      scores: rawScores.map((k, v) => MapEntry(k, v as int)),
      turnState:
          rawTurnState != null ? TurnState.fromJson(rawTurnState) : null,
      allowedActions: rawActions
          .map((e) => AllowedAction.fromJson(e as Map<String, dynamic>))
          .toList(),
      version: json['version'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'phase': phase.toJson(),
        'playerId': playerId,
        'hand': hand,
        'scores': scores,
        if (turnState != null) 'turnState': turnState!.toJson(),
        'allowedActions': allowedActions.map((a) => a.toJson()).toList(),
        'version': version,
      };
}

const Object _kUnset = Object();
