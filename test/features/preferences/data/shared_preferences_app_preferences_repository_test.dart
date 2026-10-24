import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/preferences/data/repositories/shared_preferences_app_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';

void main() {
  group('SharedPreferencesAppPreferencesRepository', () {
    test('uses light when the stored theme is absent or invalid', () async {
      final _Store store = _Store();
      final SharedPreferencesAppPreferencesRepository repository =
          SharedPreferencesAppPreferencesRepository(storage: store);

      expect(await repository.readTheme(), ThemePreference.light);
      store.strings['mattermost.app.theme'] = 'system';
      expect(await repository.readTheme(), ThemePreference.light);
    });

    test(
      'persists a dark theme independently from the update timestamp',
      () async {
        final _Store store = _Store();
        final SharedPreferencesAppPreferencesRepository repository =
            SharedPreferencesAppPreferencesRepository(storage: store);
        final DateTime checkedAt = DateTime.utc(2026, 10, 23, 12, 30);

        await repository.writeLastUpdateCheck(checkedAt);
        await repository.writeTheme(ThemePreference.dark);

        expect(await repository.readTheme(), ThemePreference.dark);
        expect(await repository.readLastUpdateCheck(), checkedAt);
      },
    );

    test('normalizes update timestamps to UTC milliseconds', () async {
      final _Store store = _Store();
      final SharedPreferencesAppPreferencesRepository repository =
          SharedPreferencesAppPreferencesRepository(storage: store);
      final DateTime localTime = DateTime(2026, 10, 23, 15);

      await repository.writeLastUpdateCheck(localTime);

      expect(await repository.readLastUpdateCheck(), localTime.toUtc());
    });
  });
}

final class _Store implements AppPreferencesStore {
  final Map<String, String> strings = <String, String>{};
  final Map<String, int> integers = <String, int>{};

  @override
  Future<String?> getString(String key) async => strings[key];

  @override
  Future<int?> getInt(String key) async => integers[key];

  @override
  Future<void> setInt(String key, int value) async {
    integers[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    strings[key] = value;
  }
}
