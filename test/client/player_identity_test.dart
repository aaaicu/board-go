import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../lib/client/shared/player_identity.dart';

void main() {
  group('PlayerIdentity', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('load() generates a UUID on first launch', () async {
      final identity = await PlayerIdentity.load();

      expect(identity.deviceId, isNotEmpty);
      // UUIDs are 36 chars: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      expect(identity.deviceId.length, equals(36));
      expect(identity.deviceId, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )));
    });

    test('load() returns same UUID on second call (stable device ID)', () async {
      final first = await PlayerIdentity.load();
      final second = await PlayerIdentity.load();

      expect(second.deviceId, equals(first.deviceId));
    });

    test('load() returns default nickname "Player" when none saved', () async {
      final identity = await PlayerIdentity.load();

      expect(identity.nickname, equals('Player'));
    });

    test('saveNickname() persists nickname across subsequent loads', () async {
      await PlayerIdentity.saveNickname('Alice');
      final identity = await PlayerIdentity.load();

      expect(identity.nickname, equals('Alice'));
    });

    test('saveNickname() does not affect deviceId', () async {
      final before = await PlayerIdentity.load();
      await PlayerIdentity.saveNickname('Bob');
      final after = await PlayerIdentity.load();

      expect(after.deviceId, equals(before.deviceId));
    });

    test('saveNickname() overwrites previous nickname', () async {
      await PlayerIdentity.saveNickname('Alice');
      await PlayerIdentity.saveNickname('Charlie');
      final identity = await PlayerIdentity.load();

      expect(identity.nickname, equals('Charlie'));
    });

    test('deviceId cannot be changed — second load always returns original', () async {
      // Pre-seed a known device ID.
      SharedPreferences.setMockInitialValues({
        'player_device_id': 'pre-seeded-device-id',
      });

      final identity = await PlayerIdentity.load();

      expect(identity.deviceId, equals('pre-seeded-device-id'));
    });
  });
}
