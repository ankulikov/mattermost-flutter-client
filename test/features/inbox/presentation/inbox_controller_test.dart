import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';

void main() {
  test(
    'refresh keeps the previous Inbox snapshot while request is pending',
    () async {
      final Completer<InboxSnapshot> refresh = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () => Future<InboxSnapshot>.value(InboxSnapshot()),
          () => refresh.future,
        ],
      );
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final InboxViewState initial = await container.read(provider.future);
      expect(initial.isRefreshing, isFalse);

      final Future<void> request = container.read(provider.notifier).refresh();
      expect(container.read(provider).value?.isRefreshing, isTrue);
      refresh.complete(InboxSnapshot());
      await request;
      expect(container.read(provider).value?.isRefreshing, isFalse);
      expect(container.read(provider).value?.refreshFailed, isFalse);
    },
  );

  test(
    'refresh failure preserves data and exposes a non-blocking error',
    () async {
      final _InboxRepository repository =
          _InboxRepository(<Future<InboxSnapshot> Function()>[
            () => Future<InboxSnapshot>.value(InboxSnapshot()),
            () => Future<InboxSnapshot>(() => throw StateError('offline')),
          ]);
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);
      await container.read(provider.notifier).refresh();
      expect(container.read(provider).hasValue, isTrue);
      expect(container.read(provider).value?.refreshFailed, isTrue);
    },
  );
}

AsyncNotifierProvider<InboxController, InboxViewState> _provider(
  InboxRepository repository,
) {
  final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>(
    (Ref ref) => AuthSession(
      serverUrl: Uri(scheme: 'https', host: 'chat.example.test'),
      userId: 'user',
      username: 'ada',
    ),
  );
  final Provider<InboxRepository> inboxProvider = Provider<InboxRepository>(
    (Ref ref) => repository,
  );
  final Provider<PostponedRepository> postponedProvider =
      Provider<PostponedRepository>((Ref ref) => const _PostponedRepository());
  return AsyncNotifierProvider.autoDispose<InboxController, InboxViewState>(
    () => InboxController(sessionProvider, inboxProvider, postponedProvider),
  );
}

final class _InboxRepository extends InboxRepository {
  _InboxRepository(this.results);
  final List<Future<InboxSnapshot> Function()> results;
  var _index = 0;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) =>
      results[_index++]();
}

final class _PostponedRepository extends PostponedRepository {
  const _PostponedRepository();
  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);
  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
}
