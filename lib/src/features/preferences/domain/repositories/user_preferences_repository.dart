import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';

/// Reads and replaces the durable preferences for the active account.
abstract interface class UserPreferencesRepository {
  Future<UserPreferences> read();

  Future<void> update(UserPreferences preferences);
}
