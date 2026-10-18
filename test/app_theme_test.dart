import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';

void main() {
  group('MattermostTheme', () {
    test('keeps the pre-preference light theme appearance', () {
      final ThemeData light = MattermostTheme.light();
      final ThemeData expected = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0058cc)),
        useMaterial3: true,
      );

      expect(light, expected);
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
    test('uses light without reading preferences while signed out', () {
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

    test('loads the active account persisted theme', () async {
      final Completer<UserPreferences> read = Completer<UserPreferences>();
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository(onRead: () => read.future);
      final ProviderContainer container = _signedInContainer(repository);
      addTearDown(container.dispose);

      expect(
        container.read(appThemeProvider).preference,
        ThemePreference.light,
      );
      expect(container.read(appThemeProvider).isLoading, isTrue);

      read.complete(const UserPreferences(theme: ThemePreference.dark));
      await pumpEventQueue();

      expect(container.read(appThemeProvider).preference, ThemePreference.dark);
      expect(container.read(appThemeProvider).isLoading, isFalse);
    });

    test('falls back to light when reading preferences fails', () async {
      final _FakeUserPreferencesRepository repository =
          _FakeUserPreferencesRepository(
            onRead: () => Future<UserPreferences>.error(
              StateError('preferences unavailable'),
            ),
          );
      final ProviderContainer container = _signedInContainer(repository);
      addTearDown(container.dispose);

      expect(container.read(appThemeProvider).isLoading, isTrue);
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
      final ProviderContainer container = _signedInContainer(repository);
      addTearDown(container.dispose);
      container.read(appThemeProvider);
      await pumpEventQueue();

      final Future<void> result = container
          .read(appThemeProvider.notifier)
          .updateTheme(ThemePreference.dark);

      expect(container.read(appThemeProvider).preference, ThemePreference.dark);
      expect(container.read(appThemeProvider).isSaving, isTrue);
      expect(repository.updatedPreferences, const <UserPreferences>[
        UserPreferences(theme: ThemePreference.dark),
      ]);

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
      final ProviderContainer container = _signedInContainer(repository);
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
      expect(repository.updatedPreferences, hasLength(2));
    });
  });
}

ProviderContainer _container(_FakeUserPreferencesRepository repository) =>
    ProviderContainer(
      overrides: [
        userPreferencesRepositoryProvider.overrideWithValue(repository),
      ],
    );

ProviderContainer _signedInContainer(
  _FakeUserPreferencesRepository repository,
) {
  final ProviderContainer container = _container(repository);
  container.read(activeAccountSessionProvider.notifier).set(_session);
  return container;
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://mattermost.example.com'),
  userId: 'user-1',
  username: 'test-user',
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
  final List<UserPreferences> updatedPreferences = <UserPreferences>[];
  int readCount = 0;

  @override
  Future<UserPreferences> read() {
    readCount += 1;
    return onRead?.call() ??
        Future<UserPreferences>.value(UserPreferences.defaults);
  }

  @override
  Future<DateTime?> readLastUpdateCheck() async => null;

  @override
  Future<void> update(UserPreferences preferences) {
    updatedPreferences.add(preferences);
    return onUpdate?.call(preferences) ?? Future<void>.value();
  }

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) async {}
}
