import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/data/providers/session_providers.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/display_settings_page.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'ada',
  );

  Future<ProviderContainer> pumpDisplaySettings(
    WidgetTester tester,
    _UserPreferencesRepository repository, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        userPreferencesRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      container.dispose();
    });
    container.read(activeAccountSessionProvider.notifier).set(session);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final ThemePreference preference = ref.watch(
              appThemeProvider.select(
                (AppThemeState state) => state.preference,
              ),
            );
            return MaterialApp(
              theme: MattermostTheme.light(),
              darkTheme: MattermostTheme.dark(),
              themeMode: preference == ThemePreference.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: const DisplaySettingsPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('shows compact light and dark choices at large text scale', (
    WidgetTester tester,
  ) async {
    await pumpDisplaySettings(
      tester,
      _UserPreferencesRepository(),
      textScale: 2,
    );

    expect(
      find.byKey(const ValueKey<String>('display-settings-compact')),
      findsOneWidget,
    );
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the expanded pane on the wide side of the breakpoint', (
    WidgetTester tester,
  ) async {
    await pumpDisplaySettings(
      tester,
      _UserPreferencesRepository(),
      size: const Size(700, 700),
      textScale: 2,
    );

    expect(
      find.byKey(const ValueKey<String>('display-settings-expanded')),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(Card)).width, lessThanOrEqualTo(760));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflects the provider selection and persists a new theme', (
    WidgetTester tester,
  ) async {
    final _UserPreferencesRepository repository = _UserPreferencesRepository(
      initial: const UserPreferences(theme: ThemePreference.dark),
    );
    final ProviderContainer container = await pumpDisplaySettings(
      tester,
      repository,
    );

    expect(
      tester
          .widget<RadioGroup<ThemePreference>>(
            find.byType(RadioGroup<ThemePreference>),
          )
          .groupValue,
      ThemePreference.dark,
    );

    await tester.tap(find.byKey(const ValueKey<String>('theme-light')));
    await tester.pumpAndSettle();

    expect(repository.updated, UserPreferences.defaults);
    expect(container.read(appThemeProvider).preference, ThemePreference.light);
    expect(
      Theme.of(
        tester.element(
          find.byKey(const ValueKey<String>('display-settings-page')),
        ),
      ).brightness,
      Brightness.light,
    );
  });

  testWidgets('keeps the pane visible and reports persistence failure', (
    WidgetTester tester,
  ) async {
    final _UserPreferencesRepository repository = _UserPreferencesRepository(
      failUpdate: true,
    );
    final ProviderContainer container = await pumpDisplaySettings(
      tester,
      repository,
    );

    await tester.tap(find.byKey(const ValueKey<String>('theme-dark')));
    await tester.pumpAndSettle();

    expect(find.text('Could not save your theme.'), findsOneWidget);
    expect(container.read(appThemeProvider).preference, ThemePreference.light);
    expect(
      tester
          .widget<RadioGroup<ThemePreference>>(
            find.byType(RadioGroup<ThemePreference>),
          )
          .groupValue,
      ThemePreference.light,
    );
    expect(
      find.byKey(const ValueKey<String>('display-settings-page')),
      findsOneWidget,
    );

    repository.failUpdate = false;
    await tester.tap(find.byKey(const ValueKey<String>('theme-dark')));
    await tester.pumpAndSettle();
    expect(container.read(appThemeProvider).preference, ThemePreference.dark);
    expect(repository.updateCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows progress and prevents overlapping updates', (
    WidgetTester tester,
  ) async {
    final Completer<void> updateCompleter = Completer<void>();
    final _UserPreferencesRepository repository = _UserPreferencesRepository(
      updateCompleter: updateCompleter,
    );
    final ProviderContainer container = await pumpDisplaySettings(
      tester,
      repository,
    );

    await tester.tap(find.byKey(const ValueKey<String>('theme-dark')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('display-settings-progress')),
      findsOneWidget,
    );
    expect(container.read(appThemeProvider).preference, ThemePreference.dark);
    expect(repository.updateCalls, 1);
    await tester.tap(find.byKey(const ValueKey<String>('theme-light')));
    await tester.pump();
    expect(repository.updateCalls, 1);

    updateCompleter.complete();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('display-settings-progress')),
      findsNothing,
    );
  });
}

final class _UserPreferencesRepository implements UserPreferencesRepository {
  _UserPreferencesRepository({
    this.initial = UserPreferences.defaults,
    this.failUpdate = false,
    this.updateCompleter,
  });

  final UserPreferences initial;
  bool failUpdate;
  final Completer<void>? updateCompleter;
  UserPreferences? updated;
  int updateCalls = 0;

  @override
  Future<UserPreferences> read() async => initial;

  @override
  Future<DateTime?> readLastUpdateCheck() async => null;

  @override
  Future<void> update(UserPreferences preferences) async {
    updateCalls += 1;
    updated = preferences;
    if (failUpdate) throw StateError('save failed');
    await updateCompleter?.future;
  }

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) async {}
}
