import '../game_pack/game_state.dart';
import 'game_log_entry.dart';
import 'player_session_state.dart';
import 'session_phase.dart';
import 'turn_state.dart';

/// Maximum number of log entries retained.
const int _kMaxLogEntries = 50;

/// Immutable snapshot of the entire lobby / session state.
///
/// [version] increments on every mutation to allow clients to detect
/// missed updates.
///
/// [log] is capped at [_kMaxLogEntries] — oldest entries are discarded.
///
/// Sprint 2 additions:
///   - [turnState]: null during lobby phase; non-null once the game starts.
///   - [gameState]: null during lobby phase; holds pack-specific game data
///     once the game is in progress.
class GameSessionState {
  final String sessionId;
  final SessionPhase phase;
  final Map<String, PlayerSessionState> players; // playerId → PlayerSessionState
  final List<String> playerOrder;
  final int version;
  final List<GameLogEntry> log;

  /// Current turn information. Null while in lobby or finished phases.
  final TurnState? turnState;

  /// Game-pack-specific state (card hands, deck, scores, etc.).
  /// Null while in lobby phase.
  final GameState? gameState;

  const GameSessionState({
    required this.sessionId,
    required this.phase,
    required this.players,
    required this.playerOrder,
    required this.version,
    required this.log,
    this.turnState,
    this.gameState,
  });

  /// Returns a new state with [entry] appended to [log].
  ///
  /// If the log already has [_kMaxLogEntries] entries the oldest one is
  /// removed before appending, keeping the list bounded.
  GameSessionState addLog(GameLogEntry entry) {
    final updated = [...log, entry];
    final trimmed = updated.length > _kMaxLogEntries
        ? updated.sublist(updated.length - _kMaxLogEntries)
        : updated;
    return copyWith(log: trimmed, version: version + 1);
  }

  GameSessionState copyWith({
    String? sessionId,
    SessionPhase? phase,
    Map<String, PlayerSessionState>? players,
    List<String>? playerOrder,
    int? version,
    List<GameLogEntry>? log,
    // Use Object? sentinel to allow explicitly setting nullable fields to null.
    Object? turnState = _kUnset,
    Object? gameState = _kUnset,
  }) =>
      GameSessionState(
        sessionId: sessionId ?? this.sessionId,
        phase: phase ?? this.phase,
        players: players ?? this.players,
        playerOrder: playerOrder ?? this.playerOrder,
        version: version ?? this.version,
        log: log ?? this.log,
        turnState: identical(turnState, _kUnset)
            ? this.turnState
            : turnState as TurnState?,
        gameState: identical(gameState, _kUnset)
            ? this.gameState
            : gameState as GameState?,
      );

  factory GameSessionState.fromJson(Map<String, dynamic> json) {
    final rawPlayers = json['players'] as Map<String, dynamic>;
    final players = rawPlayers.map(
      (k, v) => MapEntry(k, PlayerSessionState.fromJson(v as Map<String, dynamic>)),
    );

    final rawLog = (json['log'] as List<dynamic>?) ?? [];
    final log = rawLog
        .map((e) => GameLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawTurnState = json['turnState'] as Map<String, dynamic>?;
    final rawGameState = json['gameState'] as Map<String, dynamic>?;

    return GameSessionState(
      sessionId: json['sessionId'] as String,
      phase: SessionPhase.fromJson(json['phase'] as String),
      players: players,
      playerOrder: List<String>.from(json['playerOrder'] as List),
      version: json['version'] as int,
      log: log,
      turnState: rawTurnState != null ? TurnState.fromJson(rawTurnState) : null,
      gameState: rawGameState != null ? GameState.fromJson(rawGameState) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'phase': phase.toJson(),
        'players': players.map((k, v) => MapEntry(k, v.toJson())),
        'playerOrder': playerOrder,
        'version': version,
        'log': log.map((e) => e.toJson()).toList(),
        if (turnState != null) 'turnState': turnState!.toJson(),
        if (gameState != null) 'gameState': gameState!.toJson(),
      };
}

/// Sentinel used in [GameSessionState.copyWith] to distinguish "not provided"
/// from an explicitly-passed `null`.
const Object _kUnset = Object();
