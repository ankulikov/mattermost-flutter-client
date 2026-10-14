/// Theme choices that can be persisted without depending on Flutter UI types.
enum ThemePreference { light, dark }

/// Durable preferences owned by one authenticated account.
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
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is UserPreferences && other.theme == theme;
  }

  @override
  int get hashCode => theme.hashCode;
}
