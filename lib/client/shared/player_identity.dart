import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persistent device identity for a GameNode player.
///
/// The [deviceId] is a UUID v4 generated on first launch and never changed
/// afterwards (survives app restarts, changes only on reinstall).
///
/// The [nickname] is a user-editable display name that defaults to `'Player'`.
///
/// Both values are stored in [SharedPreferences].
class PlayerIdentity {
  static const _keyDeviceId = 'player_device_id';
  static const _keyNickname = 'player_nickname';
  static const _keyReconnectToken = 'player_reconnect_token';
  static const _keyReconnectServerUrl = 'player_reconnect_server_url';
  static const _defaultNickname = 'Player';

  /// Stable UUID that uniquely identifies this device installation.
  final String deviceId;

  /// User-visible display name.
  final String nickname;

  const PlayerIdentity({required this.deviceId, required this.nickname});

  /// Loads the player identity from [SharedPreferences].
  ///
  /// If no device ID exists yet, a new UUID v4 is generated and persisted
  /// immediately so that every subsequent call returns the same value.
  static Future<PlayerIdentity> load() async {
    final prefs = await SharedPreferences.getInstance();

    String? deviceId = prefs.getString(_keyDeviceId);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_keyDeviceId, deviceId);
    }

    final nickname = prefs.getString(_keyNickname) ?? _defaultNickname;
    return PlayerIdentity(deviceId: deviceId, nickname: nickname);
  }

  /// Persists [nickname] to [SharedPreferences].
  ///
  /// The [deviceId] is never mutated by this method.
  static Future<void> saveNickname(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNickname, nickname);
  }

  /// Persists [token] alongside the [serverUrl] it was issued for.
  ///
  /// Only tokens matching [serverUrl] will be returned by [loadReconnectToken],
  /// preventing a stale token from being sent to a different server.
  static Future<void> saveReconnectToken(String serverUrl, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyReconnectToken, token);
    await prefs.setString(_keyReconnectServerUrl, serverUrl);
  }

  /// Returns the saved reconnect token if it was issued by [serverUrl],
  /// or `null` if no token exists or it belongs to a different server.
  static Future<String?> loadReconnectToken(String serverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_keyReconnectServerUrl);
    if (savedUrl != serverUrl) return null;
    return prefs.getString(_keyReconnectToken);
  }

  /// Returns the server URL of the last active session, or `null` if none.
  ///
  /// Used to show a "이어하기" option on app restart.
  static Future<String?> loadLastServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyReconnectServerUrl);
    // Only return the URL if a token also exists — URL without token is useless.
    final token = prefs.getString(_keyReconnectToken);
    if (url == null || token == null) return null;
    return url;
  }

  /// Removes the saved reconnect token (e.g. on deliberate disconnect or
  /// after the server session ends).
  static Future<void> clearReconnectToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyReconnectToken);
    await prefs.remove(_keyReconnectServerUrl);
  }
}
