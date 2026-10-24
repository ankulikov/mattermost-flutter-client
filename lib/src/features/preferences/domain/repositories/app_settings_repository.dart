import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';

/// Reads and writes durable settings for this application installation.
abstract interface class AppSettingsRepository {
  Future<ThemePreference> readTheme();

  Future<void> writeTheme(ThemePreference theme);

  /// Reads the last app-update check time for automatic startup checks only.
  Future<DateTime?> readLastUpdateCheck();

  /// Records an automatic or user-initiated app-update check.
  Future<void> writeLastUpdateCheck(DateTime checkedAt);
}
