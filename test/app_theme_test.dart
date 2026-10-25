import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';

void main() {
  group('MattermostTheme', () {
    test('uses the shared component theme in both modes', () {
      for (final ThemeData theme in [
        MattermostTheme.light(),
        MattermostTheme.dark(),
      ]) {
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.appBarTheme.backgroundColor, theme.colorScheme.surface);
        expect(
          theme.navigationBarTheme.backgroundColor,
          theme.colorScheme.surfaceContainerLow,
        );
        expect(
          theme.dialogTheme.backgroundColor,
          theme.colorScheme.surfaceContainerHigh,
        );
        expect(
          theme.bottomSheetTheme.backgroundColor,
          theme.colorScheme.surfaceContainerLow,
        );
        expect(theme.dividerTheme.color, theme.colorScheme.outlineVariant);
        expect(
          _contrast(theme.colorScheme.onSurface, theme.colorScheme.surface),
          greaterThan(4.5),
        );
      }
    });

    test('supplies the dark theme', () {
      final ThemeData dark = MattermostTheme.dark();

      expect(dark.colorScheme.primary, const Color(0xff8ab4f8));
      expect(dark.useMaterial3, isTrue);
      expect(dark.appBarTheme.systemOverlayStyle, SystemUiOverlayStyle.light);
    });

    test('dark theme keeps primary and surface text contrast accessible', () {
      final ColorScheme colors = MattermostTheme.dark().colorScheme;

      expect(_contrast(colors.onSurface, colors.surface), greaterThan(7));
      expect(_contrast(colors.onPrimary, colors.primary), greaterThan(4.5));
      expect(colors.surfaceContainerLow, isNot(colors.surface));
      expect(colors.surfaceContainerHighest, isNot(colors.surface));
    });
  });

  group('AppThemeController', () {
    test('uses the bootstrapped light preference while signed out', () {
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository();
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      expect(
        container.read(appThemeProvider).preference,
        ThemePreference.light,
      );
      expect(container.read(appThemeProvider).isLoading, isFalse);
      expect(repository.readCount, 0);
    });

    test('uses the bootstrapped theme synchronously', () {
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository();
      final ProviderContainer container = _container(
        repository,
        initial: ThemePreference.dark,
      );
      addTearDown(container.dispose);

      expect(container.read(appThemeProvider).preference, ThemePreference.dark);
      expect(container.read(appThemeProvider).isLoading, isFalse);
      expect(repository.readCount, 0);
    });

    test('does not read preferences after the boot snapshot', () async {
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository(
            onRead: () => Future<UserPreferences>.error(
              StateError('preferences unavailable'),
            ),
          );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);

      expect(container.read(appThemeProvider).isLoading, isFalse);
      await pumpEventQueue();

      expect(
        container.read(appThemeProvider),
        isA<AppThemeState>()
            .having(
              (AppThemeState value) => value.preference,
              'preference',
              ThemePreference.light,
            )
            .having(
              (AppThemeState value) => value.isLoading,
              'isLoading',
              isFalse,
            ),
      );
    });

    test('applies an update before persistence finishes', () async {
      final Completer<void> update = Completer<void>();
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository(onUpdate: (_) => update.future);
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      container.read(appThemeProvider);
      await pumpEventQueue();

      final Future<void> result = container
          .read(appThemeProvider.notifier)
          .updateTheme(ThemePreference.dark);

      expect(container.read(appThemeProvider).preference, ThemePreference.dark);
      expect(container.read(appThemeProvider).isSaving, isTrue);
      expect(repository.updatedThemes, <ThemePreference>[ThemePreference.dark]);

      update.complete();
      await result;

      expect(container.read(appThemeProvider).isSaving, isFalse);
    });

    test('rolls back a failed save so the theme can be retried', () async {
      final Completer<void> update = Completer<void>();
      int updateAttempts = 0;
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository(
            onUpdate: (_) {
              updateAttempts += 1;
              return updateAttempts == 1 ? update.future : Future<void>.value();
            },
          );
      final ProviderContainer container = _container(repository);
      addTearDown(container.dispose);
      container.read(appThemeProvider);
      await pumpEventQueue();

      final Future<void> result = container
          .read(appThemeProvider.notifier)
          .updateTheme(ThemePreference.dark);
      final StateError error = StateError('database unavailable');
      update.completeError(error);

      await expectLater(result, throwsA(same(error)));
      expect(
        container.read(appThemeProvider).preference,
        ThemePreference.light,
      );
      expect(container.read(appThemeProvider).isSaving, isFalse);

      await container
          .read(appThemeProvider.notifier)
          .updateTheme(ThemePreference.dark);

      expect(container.read(appThemeProvider).preference, ThemePreference.dark);
      expect(repository.updatedThemes, hasLength(2));
    });
  });
}

ProviderContainer _container(
  _FakeUserPreferencesRepository repository, {
  ThemePreference initial = ThemePreference.light,
}) => ProviderContainer(
  overrides: [
    appSettingsRepositoryProvider.overrideWithValue(repository),
    initialAppThemeProvider.overrideWithValue(initial),
  ],
);

double _contrast(Color first, Color second) {
  final double lighter = first.computeLuminance() > second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final double darker = first.computeLuminance() > second.computeLuminance()
      ? second.computeLuminance()
      : first.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

final class _FakeUserPreferencesRepository
    implements UserPreferencesRepository {
  _FakeUserPreferencesRepository({this.onRead, this.onUpdate});

  final Future<UserPreferences> Function()? onRead;
  final Future<void> Function(UserPreferences preferences)? onUpdate;
  final List<ThemePreference> updatedThemes = <ThemePreference>[];
  int readCount = 0;

  Future<UserPreferences> read() {
    readCount += 1;
    return onRead?.call() ??
        Future<UserPreferences>.value(UserPreferences.defaults);
  }

  @override
  Future<DateTime?> readLastUpdateCheck() async => null;

  Future<void> update(UserPreferences preferences) {
    return onUpdate?.call(preferences) ?? Future<void>.value();
  }

  @override
  Future<ThemePreference> readTheme() async => ThemePreference.light;

  @override
  Future<void> writeTheme(ThemePreference theme) {
    updatedThemes.add(theme);
    return onUpdate?.call(UserPreferences(theme: theme)) ??
        Future<void>.value();
  }

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) async {}
}
