import 'dart:convert';
import 'dart:math';

import '../shared/messages/lobby_state_message.dart';

/// Abstraction over a WebSocket sink so [SessionManager] can be tested
/// without a real network connection.
abstract class SessionSink {
  void add(String data);
  Future<void> close();
}

class _PlayerSession {
  final String displayName;
  final SessionSink? sink; // null when the player is disconnected
  final bool isConnected;

  _PlayerSession({
    required this.displayName,
    required this.sink,
    required this.isConnected,
  });

  _PlayerSession copyWith({
    String? displayName,
    SessionSink? sink,
    bool? isConnected,
  }) =>
      _PlayerSession(
        displayName: displayName ?? this.displayName,
        sink: sink ?? this.sink,
        isConnected: isConnected ?? this.isConnected,
      );
}

/// Tracks all connected player sessions and provides send/broadcast helpers.
///
/// Sprint 1 additions:
///   - per-player ready state ([setReady], [isReady])
///   - reconnect tokens ([getReconnectToken], [findPlayerByReconnectToken])
///   - lobby state snapshot ([buildLobbyState], [isReadyToStart])
///
/// Sprint 3 additions:
///   - [markDisconnected]: marks a player as offline without removing their
///     seat or reconnect token.
///   - [reconnect]: re-attaches a new sink to an existing (disconnected) seat.
///   - [isReadyToStart] now only counts *connected* players.
///   - [buildLobbyState] includes [LobbyStatePlayerInfo.isConnected] for all
///     seats (connected and disconnected alike) so the GameBoard can render
///     an offline indicator.
class SessionManager {
  /// playerId → session (may be connected or disconnected)
  final Map<String, _PlayerSession> _sessions = {};

  /// playerId → isReady
  final Map<String, bool> _readyStates = {};

  /// playerId → reconnectToken (stable across re-register calls)
  final Map<String, String> _reconnectTokenByPlayerId = {};

  /// reconnectToken → playerId (reverse index)
  final Map<String, String> _reconnectTokens = {};

  // ---------------------------------------------------------------------------
  // Core session management
  // ---------------------------------------------------------------------------

  /// Returns the total number of known seats (connected + disconnected).
  int get playerCount => _sessions.length;

  /// Returns the IDs of all known players (connected and disconnected).
  Iterable<String> get playerIds => _sessions.keys;

  /// Returns `true` if [playerId] is currently connected.
  bool isConnected(String playerId) =>
      _sessions[playerId]?.isConnected == true;

  String? displayName(String playerId) => _sessions[playerId]?.displayName;

  /// Adds (or replaces) the session for [playerId].
  ///
  /// Ready state is reset to false on every new registration so that a player
  /// who disconnects and reconnects must explicitly signal ready again.
  void register({
    required String playerId,
    required String displayName,
    required SessionSink sink,
  }) {
    _sessions[playerId] = _PlayerSession(
      displayName: displayName,
      sink: sink,
      isConnected: true,
    );
    _readyStates[playerId] = false;
  }

  /// Removes the session for [playerId] and clears the ready state.
  ///
  /// The reconnect token is intentionally preserved so the player can
  /// reclaim the same seat after an unintended disconnect.
  void unregister(String playerId) {
    _sessions.remove(playerId);
    _readyStates.remove(playerId);
  }

  /// Marks [playerId] as disconnected without removing their seat.
  ///
  /// The player's nickname, ready state, and reconnect token are all preserved.
  /// The underlying sink is nulled out so no messages will be sent to the
  /// stale connection.
  ///
  /// If [playerId] is not found this is a no-op.
  void markDisconnected(String playerId) {
    final session = _sessions[playerId];
    if (session == null) return;
    _sessions[playerId] = _PlayerSession(
      displayName: session.displayName,
      sink: null,
      isConnected: false,
    );
  }

  /// Re-attaches [newSink] to an existing (disconnected) seat identified by
  /// [playerId] and marks the player as connected again.
  ///
  /// If [playerId] is not found this is a no-op.
  void reconnect({required String playerId, required SessionSink newSink}) {
    final session = _sessions[playerId];
    if (session == null) return;
    _sessions[playerId] = _PlayerSession(
      displayName: session.displayName,
      sink: newSink,
      isConnected: true,
    );
  }

  /// Sends [data] to the specified player.  No-op if the player is not found
  /// or is currently disconnected.
  void send(String playerId, String data) {
    final session = _sessions[playerId];
    if (session != null && session.isConnected) {
      session.sink?.add(data);
    }
  }

  /// Alias for [send] used by the game-loop pipeline for PLAYER_VIEW delivery.
  ///
  /// Sending the player-specific view through a named method makes the
  /// intent explicit at the call site.
  void sendToPlayer(String playerId, Map<String, dynamic> data) {
    send(playerId, jsonEncode(data));
  }

  /// Broadcasts [data] to all *connected* players.
  ///
  /// Used for BOARD_VIEW delivery after every game action.
  void broadcastBoardView(Map<String, dynamic> data) {
    broadcast(jsonEncode(data));
  }

  /// Sends [data] to all connected players, optionally excluding one.
  void broadcast(String data, {String? excludePlayerId}) {
    for (final entry in _sessions.entries) {
      if (entry.key == excludePlayerId) continue;
      if (!entry.value.isConnected) continue;
      entry.value.sink?.add(data);
    }
  }

  // ---------------------------------------------------------------------------
  // Ready state
  // ---------------------------------------------------------------------------

  /// Marks or clears the ready flag for [playerId].
  void setReady(String playerId, bool ready) {
    if (_sessions.containsKey(playerId)) {
      _readyStates[playerId] = ready;
    }
  }

  /// Returns the ready state for [playerId], defaulting to false.
  bool isReady(String playerId) => _readyStates[playerId] ?? false;

  /// Returns true when at least 1 *connected* player exists and all of them
  /// have set their ready flag to true.
  bool isReadyToStart() {
    final connectedIds =
        _sessions.keys.where((id) => _sessions[id]!.isConnected).toList();
    if (connectedIds.isEmpty) return false;
    return connectedIds.every((id) => _readyStates[id] == true);
  }

  // ---------------------------------------------------------------------------
  // Reconnect tokens
  // ---------------------------------------------------------------------------

  /// Returns the reconnect token for [playerId].
  ///
  /// If one has not been issued yet a new UUID v4 token is generated,
  /// stored and returned.
  String getReconnectToken(String playerId) {
    final existing = _reconnectTokenByPlayerId[playerId];
    if (existing != null) return existing;

    final token = _generateUuid();
    _reconnectTokenByPlayerId[playerId] = token;
    _reconnectTokens[token] = playerId;
    return token;
  }

  /// Looks up which player holds [token].  Returns null if unknown.
  String? findPlayerByReconnectToken(String token) =>
      _reconnectTokens[token];

  // ---------------------------------------------------------------------------
  // Lobby snapshot
  // ---------------------------------------------------------------------------

  /// Builds a [LobbyStateMessage] from the current session state.
  ///
  /// Includes *both* connected and disconnected players so the GameBoard can
  /// render an offline indicator.  The [LobbyStateMessage.canStart] flag is
  /// computed using [isReadyToStart] which only counts connected players.
  LobbyStateMessage buildLobbyState() {
    final players = _sessions.entries.map((e) {
      return LobbyStatePlayerInfo(
        playerId: e.key,
        nickname: e.value.displayName,
        isReady: _readyStates[e.key] ?? false,
        isConnected: e.value.isConnected,
      );
    }).toList();

    return LobbyStateMessage(
      players: players,
      canStart: isReadyToStart(),
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static final _rng = Random.secure();

  /// Generates a pseudo-UUID v4 string without external dependencies.
  static String _generateUuid() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    // Set version 4 bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant bits
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(hex).toList();
    return '${b[0]}${b[1]}${b[2]}${b[3]}-'
        '${b[4]}${b[5]}-'
        '${b[6]}${b[7]}-'
        '${b[8]}${b[9]}-'
        '${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
  }
}
