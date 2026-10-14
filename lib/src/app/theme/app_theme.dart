import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';

/// Themes supplied by the application composition root.
///
/// Widgets consume these values through [Theme.of] and remain independent of
/// how the user selects or persists a theme.
abstract final class MattermostTheme {
  static const Color _brandBlue = Color(0xff0058cc);

  /// Matches the pre-theme-preference application default exactly.
  ///
  /// Keep this branch free of component overrides: the existing light UI relies
  /// on Material's seed-derived surface and outline tones.
  static ThemeData light() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _brandBlue),
    useMaterial3: true,
  );

  static ThemeData dark() => _theme(
    ColorScheme.fromSeed(
      seedColor: const Color(0xff6ea8fe),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xff8ab4f8),
      onPrimary: const Color(0xff072b55),
      primaryContainer: const Color(0xff173f75),
      onPrimaryContainer: const Color(0xffd6e6ff),
      secondary: const Color(0xffb4c7e7),
      onSecondary: const Color(0xff1e3049),
      secondaryContainer: const Color(0xff2b3d57),
      onSecondaryContainer: const Color(0xffd9e7ff),
      error: const Color(0xffffb4ab),
      onError: const Color(0xff690005),
      errorContainer: const Color(0xff93000a),
      onErrorContainer: const Color(0xffffdad6),
      surface: const Color(0xff171c24),
      onSurface: const Color(0xfff1f3f6),
      surfaceContainerLowest: const Color(0xff10151c),
      surfaceContainerLow: const Color(0xff1b212a),
      surfaceContainer: const Color(0xff202731),
      surfaceContainerHigh: const Color(0xff29323e),
      surfaceContainerHighest: const Color(0xff333e4c),
      onSurfaceVariant: const Color(0xffc4cbd5),
      outline: const Color(0xff8e98a7),
      outlineVariant: const Color(0xff3e4958),
      shadow: Colors.black,
      scrim: Colors.black,
    ),
  );

  static ThemeData _theme(ColorScheme colors) {
    final bool isDark = colors.brightness == Brightness.dark;
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      brightness: colors.brightness,
      scaffoldBackgroundColor: colors.surface,
      canvasColor: colors.surface,
      dividerColor: colors.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: TextStyle(color: colors.onInverseSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        modalBackgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// The selected theme and any persistence work currently in flight.
///
/// [preference] always has a usable value. It is light while signed out and
/// while an account's stored preferences are loading or cannot be read.
final class AppThemeState {
  const AppThemeState({
    this.preference = ThemePreference.light,
    this.isLoading = false,
    this.isSaving = false,
  });

  final ThemePreference preference;
  final bool isLoading;
  final bool isSaving;

  AppThemeState copyWith({
    ThemePreference? preference,
    bool? isLoading,
    bool? isSaving,
  }) => AppThemeState(
    preference: preference ?? this.preference,
    isLoading: isLoading ?? this.isLoading,
    isSaving: isSaving ?? this.isSaving,
  );
}

final NotifierProvider<AppThemeController, AppThemeState> appThemeProvider =
    NotifierProvider<AppThemeController, AppThemeState>(AppThemeController.new);

/// Owns the account-scoped theme selection at the application root.
///
/// Reads fail closed to the light theme. Updates are optimistic so the selected
/// theme is visible immediately. A persistence failure restores the last saved
/// selection and is rethrown so the settings UI can offer non-blocking feedback
/// and leave the failed choice available to retry.
final class AppThemeController extends Notifier<AppThemeState> {
  int _generation = 0;
  UserPreferences _preferences = UserPreferences.defaults;
  UserPreferencesRepository? _repository;

  @override
  AppThemeState build() {
    final session = ref.watch(activeAccountSessionProvider);
    final int generation = ++_generation;
    _preferences = UserPreferences.defaults;
    _repository = null;

    if (session == null) return const AppThemeState();

    final UserPreferencesRepository repository = ref.watch(
      userPreferencesRepositoryProvider,
    );
    _repository = repository;
    unawaited(_load(repository, generation));
    return const AppThemeState(isLoading: true);
  }

  Future<void> _load(
    UserPreferencesRepository repository,
    int generation,
  ) async {
    UserPreferences preferences;
    try {
      preferences = await repository.read();
    } on Object {
      preferences = UserPreferences.defaults;
    }
    if (!_isCurrent(repository, generation)) return;

    _preferences = preferences;
    state = AppThemeState(preference: preferences.theme);
  }

  /// Selects [preference] immediately and then saves it for this account.
  ///
  /// A failed save restores the previous selection and rethrows the error so
  /// callers can provide localized, non-blocking feedback.
  Future<void> updateTheme(ThemePreference preference) async {
    final UserPreferencesRepository? repository = _repository;
    if (repository == null) {
      throw StateError('Theme preferences require an active account');
    }
    if (state.isSaving) {
      throw StateError('A theme preference update is already in progress');
    }

    final int generation = ++_generation;
    final UserPreferences previousPreferences = _preferences;
    final UserPreferences preferences = _preferences.copyWith(
      theme: preference,
    );
    _preferences = preferences;
    state = AppThemeState(preference: preference, isSaving: true);

    try {
      await repository.update(preferences);
    } on Object {
      if (_isCurrent(repository, generation)) {
        _preferences = previousPreferences;
        state = AppThemeState(preference: previousPreferences.theme);
      }
      rethrow;
    }

    if (_isCurrent(repository, generation)) {
      state = state.copyWith(isSaving: false);
    }
  }

  bool _isCurrent(UserPreferencesRepository repository, int generation) =>
      identical(_repository, repository) && _generation == generation;
}
