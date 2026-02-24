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
}
