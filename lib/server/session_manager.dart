/// Abstraction over a WebSocket sink so [SessionManager] can be tested
/// without a real network connection.
abstract class SessionSink {
  void add(String data);
  Future<void> close();
}

class _PlayerSession {
  final String displayName;
  final SessionSink sink;

  _PlayerSession({required this.displayName, required this.sink});
}

/// Tracks all connected player sessions and provides send/broadcast helpers.
class SessionManager {
  final Map<String, _PlayerSession> _sessions = {};

  int get playerCount => _sessions.length;

  Iterable<String> get playerIds => _sessions.keys;

  bool isConnected(String playerId) => _sessions.containsKey(playerId);

  String? displayName(String playerId) => _sessions[playerId]?.displayName;

  /// Adds (or replaces) the session for [playerId].
  void register({
    required String playerId,
    required String displayName,
    required SessionSink sink,
  }) {
    _sessions[playerId] = _PlayerSession(displayName: displayName, sink: sink);
  }

  /// Removes the session for [playerId].
  void unregister(String playerId) {
    _sessions.remove(playerId);
  }

  /// Sends [data] to the specified player.  No-op if the player is not found.
  void send(String playerId, String data) {
    _sessions[playerId]?.sink.add(data);
  }

  /// Sends [data] to all connected players, optionally excluding one.
  void broadcast(String data, {String? excludePlayerId}) {
    for (final entry in _sessions.entries) {
      if (entry.key != excludePlayerId) {
        entry.value.sink.add(data);
      }
    }
  }
}
