import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';

export 'theme_preference.dart';

/// Compatibility alias for the legacy account-scoped Drift adapter.
@Deprecated(
  'Legacy account-scoped preferences are retained for migration only.',
)
final class UserPreferences {
  const UserPreferences({required this.theme});

  static const UserPreferences defaults = UserPreferences(
    theme: ThemePreference.light,
  );

  final ThemePreference theme;

  UserPreferences copyWith({ThemePreference? theme}) {
    return UserPreferences(theme: theme ?? this.theme);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreferences && other.theme == theme;

  @override
  int get hashCode => theme.hashCode;
}
