import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/app_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Process-wide application preferences backed by the non-caching API.
///
/// These settings deliberately have no Mattermost account scope: they control
/// local application behavior before session restoration has completed.
final class SharedPreferencesAppPreferencesRepository
    implements AppSettingsRepository {
  SharedPreferencesAppPreferencesRepository({AppPreferencesStore? storage})
    : _storage = storage ?? _SharedPreferencesStore(SharedPreferencesAsync());

  static const String _themeKey = 'mattermost.app.theme';
  static const String _lastUpdateCheckKey =
      'mattermost.app.last_update_check_utc_ms';

  final AppPreferencesStore _storage;

  @override
  Future<ThemePreference> readTheme() async {
    final String? value = await _storage.getString(_themeKey);
    return switch (value) {
      'dark' => ThemePreference.dark,
      'light' || _ => ThemePreference.light,
    };
  }

  @override
  Future<void> writeTheme(ThemePreference theme) =>
      _storage.setString(_themeKey, theme.name);

  @override
  Future<DateTime?> readLastUpdateCheck() async {
    final int? milliseconds = await _storage.getInt(_lastUpdateCheckKey);
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) => _storage.setInt(
    _lastUpdateCheckKey,
    checkedAt.toUtc().millisecondsSinceEpoch,
  );
}

/// Minimal storage surface that keeps preference mapping independently testable.
abstract interface class AppPreferencesStore {
  Future<String?> getString(String key);
  Future<int?> getInt(String key);
  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
}

final class _SharedPreferencesStore implements AppPreferencesStore {
  const _SharedPreferencesStore(this._storage);

  final SharedPreferencesAsync _storage;

  @override
  Future<String?> getString(String key) => _storage.getString(key);

  @override
  Future<int?> getInt(String key) => _storage.getInt(key);

  @override
  Future<void> setString(String key, String value) =>
      _storage.setString(key, value);

  @override
  Future<void> setInt(String key, int value) => _storage.setInt(key, value);
}
