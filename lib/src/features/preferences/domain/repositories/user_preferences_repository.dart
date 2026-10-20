import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';

/// Reads and replaces the durable preferences for the active account.
abstract interface class UserPreferencesRepository {
  Future<UserPreferences> read();

  Future<void> update(UserPreferences preferences);

  /// Reads the last app-update check time for automatic startup checks only.
  Future<DateTime?> readLastUpdateCheck();

  /// Records an automatic or user-initiated app-update check.
  Future<void> writeLastUpdateCheck(DateTime checkedAt);
}
