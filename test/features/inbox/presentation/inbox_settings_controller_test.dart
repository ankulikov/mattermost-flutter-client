import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_settings_controller.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  test(
    'a retry cancels a stale settings load and keeps the newer form',
    () async {
      final Completer<InboxSettingsSnapshot> first =
          Completer<InboxSettingsSnapshot>();
      final Completer<InboxSettingsSnapshot> second =
          Completer<InboxSettingsSnapshot>();
      RequestCancellation? firstCancellation;
      final _ControlledSettingsRepository repository =
          _ControlledSettingsRepository(
            loads: <Future<InboxSettingsSnapshot> Function()>[
              () {
                firstCancellation = RequestCancellation.current;
                return first.future;
              },
              () => second.future,
            ],
          );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          inboxSettingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final ProviderSubscription<AsyncValue<InboxSettingsViewState>>
      subscription = container.listen(inboxSettingsProvider, (_, _) {});
      addTearDown(subscription.close);

      final Future<InboxSettingsViewState> staleLoad = container.read(
        inboxSettingsProvider.future,
      );
      await _waitUntil(() => firstCancellation != null);
      container.read(inboxSettingsProvider.notifier).retry();
      await _waitUntil(() => repository.loadCount == 2);

      expect(firstCancellation!.isCancelled, isTrue);
      second.complete(
        const InboxSettingsSnapshot(
          settings: InboxSettings(enabled: false),
          state: InboxSettingsLoadState.parsed,
        ),
      );
      await _waitUntil(
        () =>
            container.read(inboxSettingsProvider).value?.settings.enabled ==
            false,
      );
      first.complete(const InboxSettingsSnapshot.defaults());
      await staleLoad.catchError(
        (Object _) => const InboxSettingsViewState(
          snapshot: InboxSettingsSnapshot.defaults(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(inboxSettingsProvider).requireValue.settings.enabled,
        isFalse,
      );
    },
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

final class _ControlledSettingsRepository extends InboxSettingsRepository {
  _ControlledSettingsRepository({required this.loads});

  final List<Future<InboxSettingsSnapshot> Function()> loads;
  var loadCount = 0;

  @override
  Future<InboxSettingsSnapshot> load({required AuthSession session}) {
    loadCount += 1;
    return loads.removeAt(0)();
  }

  @override
  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
  }) => Future<void>.value();
}
