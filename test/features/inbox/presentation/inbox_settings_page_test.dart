import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_settings_page.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('loads safe default Inbox settings', (WidgetTester tester) async {
    final _SettingsRepository repository = _SettingsRepository(
      loads: <FutureOr<InboxSettingsSnapshot> Function()>[
        () => const InboxSettingsSnapshot.defaults(),
      ],
    );

    await _pumpSettings(tester, repository: repository);

    expect(find.text(InboxStrings.settingsTitle), findsOneWidget);
    expect(find.text(InboxStrings.desktopPolicyTitle), findsOneWidget);
    expect(find.text(InboxStrings.settingsDirectMessages), findsOneWidget);
    expect(find.text(InboxStrings.settingsShowMessagePreview), findsOneWidget);
    expect(_switchValue(tester, InboxStrings.settingsDirectMessages), isTrue);
    expect(
      find.bySemanticsLabel(InboxStrings.desktopPolicySemantics),
      findsOneWidget,
    );
  });

  testWidgets('shows initial failure and retries loading settings', (
    WidgetTester tester,
  ) async {
    final _SettingsRepository repository = _SettingsRepository(
      loads: <FutureOr<InboxSettingsSnapshot> Function()>[
        () => Future<InboxSettingsSnapshot>.error(StateError('offline')),
        () => const InboxSettingsSnapshot.defaults(),
      ],
    );

    await _pumpSettings(tester, repository: repository);

    expect(find.text(InboxStrings.settingsLoadFailed), findsOneWidget);
    await tester.tap(find.text(InboxStrings.retry));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
    expect(find.text(InboxStrings.settingsDirectMessages), findsOneWidget);
  });

  testWidgets('saves changed settings and preserves opaque fields', (
    WidgetTester tester,
  ) async {
    final InboxSettings loaded = InboxSettings(
      additionalFields: const <String, Object?>{'future_root': 'retained'},
      sources: const InboxSourceSettings(
        additionalFields: <String, Object?>{'future_source': true},
      ),
      postponed: const InboxPostponedSettings(
        additionalFields: <String, Object?>{'future_postponed': 7},
      ),
      directGrouping: const InboxDirectGroupingSettings(
        additionalFields: <String, Object?>{'future_grouping': 'value'},
      ),
    );
    final _SettingsRepository repository = _SettingsRepository(
      loads: <FutureOr<InboxSettingsSnapshot> Function()>[
        () => InboxSettingsSnapshot(
          settings: loaded,
          state: InboxSettingsLoadState.parsed,
        ),
      ],
    );

    await _pumpSettings(tester, repository: repository);

    await _tapSwitch(tester, InboxStrings.settingsDirectMessages);
    expect(_switchValue(tester, InboxStrings.settingsDirectMessages), isFalse);
    await _tapSwitch(tester, InboxStrings.settingsShowMessagePreview);
    expect(
      _switchValue(tester, InboxStrings.settingsShowMessagePreview),
      isTrue,
    );
    await _scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey<String>('inbox-settings-save')));
    await tester.pumpAndSettle();

    expect(repository.saved, hasLength(1));
    final InboxSettings saved = repository.saved.single;
    expect(saved.sources.directMessages, isFalse);
    expect(saved.inAppNotification.showMessagePreview, isTrue);
    expect(saved.additionalFields, loaded.additionalFields);
    expect(saved.sources.additionalFields, loaded.sources.additionalFields);
    expect(saved.postponed.additionalFields, loaded.postponed.additionalFields);
    expect(
      saved.directGrouping.additionalFields,
      loaded.directGrouping.additionalFields,
    );
  });

  testWidgets('keeps the edited form visible after a save failure', (
    WidgetTester tester,
  ) async {
    final _SettingsRepository repository = _SettingsRepository(
      loads: <FutureOr<InboxSettingsSnapshot> Function()>[
        () => const InboxSettingsSnapshot.defaults(),
      ],
      saves: <FutureOr<void> Function(InboxSettings settings)>[
        (InboxSettings settings) => Future<void>.error(StateError('offline')),
      ],
    );

    await _pumpSettings(tester, repository: repository);

    await _tapSwitch(tester, InboxStrings.settingsMentions);
    await _scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey<String>('inbox-settings-save')));
    await tester.pumpAndSettle();

    expect(find.text(InboxStrings.settingsSaveFailed), findsOneWidget);
    expect(_switchValue(tester, InboxStrings.settingsMentions), isFalse);
    expect(repository.saved.single.sources.mentions, isFalse);
  });

  testWidgets('desktop policy is read only and not a duplicate setting', (
    WidgetTester tester,
  ) async {
    final _SettingsRepository repository = _SettingsRepository(
      loads: <FutureOr<InboxSettingsSnapshot> Function()>[
        () => const InboxSettingsSnapshot.defaults(),
      ],
    );

    await _pumpSettings(tester, repository: repository);

    expect(find.text(InboxStrings.desktopPolicyDescription), findsOneWidget);
    expect(
      find.bySemanticsLabel(InboxStrings.desktopPolicySemantics),
      findsOneWidget,
    );
    expect(find.text('Desktop all messages'), findsNothing);
    expect(find.text('Desktop threads'), findsNothing);
  });

  testWidgets(
    'uses compact and expanded layouts and remains usable at large text scale',
    (WidgetTester tester) async {
      final _SettingsRepository repository = _SettingsRepository(
        loads: <FutureOr<InboxSettingsSnapshot> Function()>[
          () => const InboxSettingsSnapshot.defaults(),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(719, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(
        tester,
        repository: repository,
        textScaler: const TextScaler.linear(1.8),
      );

      expect(
        find.byKey(const ValueKey<String>('inbox-settings-compact-layout')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(720, 1100));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('inbox-settings-expanded-layout')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(InboxStrings.settingsDirectMessages),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required InboxSettingsRepository repository,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWithValue(_session),
        inboxSettingsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: const MaterialApp(home: InboxSettingsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSwitch(WidgetTester tester, String label) async {
  final Finder tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(SwitchListTile),
  );
  await tester.scrollUntilVisible(tile, 240);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _scrollToSave(WidgetTester tester) => tester.scrollUntilVisible(
  find.byKey(const ValueKey<String>('inbox-settings-save')),
  320,
);

bool _switchValue(WidgetTester tester, String label) {
  final Finder tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(SwitchListTile),
  );
  return tester.widget<SwitchListTile>(tile).value;
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

final class _SettingsRepository extends InboxSettingsRepository {
  _SettingsRepository({
    required this.loads,
    this.saves = const <FutureOr<void> Function(InboxSettings settings)>[],
  });

  final List<FutureOr<InboxSettingsSnapshot> Function()> loads;
  final List<FutureOr<void> Function(InboxSettings settings)> saves;
  final List<InboxSettings> saved = <InboxSettings>[];
  var loadCount = 0;

  @override
  Future<InboxSettingsSnapshot> load({required AuthSession session}) async {
    loadCount += 1;
    return await loads.removeAt(0)();
  }

  @override
  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
  }) async {
    saved.add(settings);
    if (saves.isNotEmpty) await saves.removeAt(0)(settings);
  }
}
