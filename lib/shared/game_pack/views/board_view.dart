import '../../game_session/game_log_entry.dart';
import '../../game_session/session_phase.dart';
import '../../game_session/turn_state.dart';

/// The public board state broadcast to the GameBoard (iPad) after every action.
///
/// Does NOT contain any player's private hand — all hand data is stripped
/// so the tablet display remains neutral.
class BoardView {
  final SessionPhase phase;

  /// playerId → score (public information visible to everyone).
  final Map<String, int> scores;

  /// Null while in lobby phase.
  final TurnState? turnState;

  /// Number of cards remaining in the draw pile.
  final int deckRemaining;

  /// The top (up to) 5 cards of the discard pile, most-recent last.
  final List<String> discardPile;

  /// The most recent (up to) 10 log entries.
  final List<GameLogEntry> recentLog;

  /// Monotonically increasing version counter mirroring [GameSessionState.version].
  final int version;

  const BoardView({
    required this.phase,
    required this.scores,
    required this.turnState,
    required this.deckRemaining,
    required this.discardPile,
    required this.recentLog,
    required this.version,
  });

  BoardView copyWith({
    SessionPhase? phase,
    Map<String, int>? scores,
    Object? turnState = _kUnset,
    int? deckRemaining,
    List<String>? discardPile,
    List<GameLogEntry>? recentLog,
    int? version,
  }) =>
      BoardView(
        phase: phase ?? this.phase,
        scores: scores ?? this.scores,
        turnState: identical(turnState, _kUnset)
            ? this.turnState
            : turnState as TurnState?,
        deckRemaining: deckRemaining ?? this.deckRemaining,
        discardPile: discardPile ?? this.discardPile,
        recentLog: recentLog ?? this.recentLog,
        version: version ?? this.version,
      );

  factory BoardView.fromJson(Map<String, dynamic> json) {
    final rawTurnState = json['turnState'] as Map<String, dynamic>?;
    final rawLog = (json['recentLog'] as List<dynamic>?) ?? [];
    final rawDiscardPile = (json['discardPile'] as List<dynamic>?) ?? [];
    final rawScores = (json['scores'] as Map<String, dynamic>?) ?? {};

    return BoardView(
      phase: SessionPhase.fromJson(json['phase'] as String),
      scores: rawScores.map((k, v) => MapEntry(k, v as int)),
      turnState:
          rawTurnState != null ? TurnState.fromJson(rawTurnState) : null,
      deckRemaining: json['deckRemaining'] as int,
      discardPile: List<String>.from(rawDiscardPile),
      recentLog: rawLog
          .map((e) => GameLogEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      version: json['version'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'phase': phase.toJson(),
        'scores': scores,
        if (turnState != null) 'turnState': turnState!.toJson(),
        'deckRemaining': deckRemaining,
        'discardPile': discardPile,
        'recentLog': recentLog.map((e) => e.toJson()).toList(),
        'version': version,
      };
}

const Object _kUnset = Object();
