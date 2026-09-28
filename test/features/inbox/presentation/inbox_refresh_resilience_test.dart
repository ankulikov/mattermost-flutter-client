import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';

void main() {
  test('a newer refresh cancels the superseded repository request', () async {
    final _RefreshRepository repository = _RefreshRepository();
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(_provider(repository).future);

    final Future<void> first = container
        .read(_provider(repository).notifier)
        .refresh();
    await repository.firstRefreshStarted.future;
    final Future<void> second = container
        .read(_provider(repository).notifier)
        .refresh();
    await repository.firstRefreshCancelled.future;

    repository.secondRefresh.complete(_snapshot('fresh'));
    await Future.wait(<Future<void>>[first, second]);

    expect(repository.firstRefreshWasCancelled, isTrue);
    expect(
      container
          .read(_provider(repository))
          .requireValue
          .snapshot
          .newItems
          .single
          .postIds,
      <String>['fresh'],
    );
  });

  test('partial refresh preserves the previous source projection', () async {
    final _SequenceRepository repository = _SequenceRepository(<InboxSnapshot>[
      _snapshot('old'),
      InboxSnapshot(
        completeness: InboxCompleteness.truncated,
        diagnosticsCodes: const <InboxSourceDiagnosticCode>[
          InboxSourceDiagnosticCode.sourceRequestFailed,
        ],
        sourceFailures: const <InboxSourceFailure>[
          InboxSourceFailure(scope: InboxSourceScope.unreadChannelPosts),
        ],
      ),
    ]);
    final ProviderContainer container = _container(repository);
    addTearDown(container.dispose);
    await container.read(_provider(repository).future);

    await container.read(_provider(repository).notifier).refresh();
    final InboxSnapshot result = container
        .read(_provider(repository))
        .requireValue
        .snapshot;

    expect(result.newItems.single.postIds, <String>['old']);
    expect(result.completeness, InboxCompleteness.truncated);
    expect(
      result.sourceFailures,
      contains(
        const InboxSourceFailure(scope: InboxSourceScope.unreadChannelPosts),
      ),
    );
  });
}

final Provider<AuthSession?> _sessionProvider = Provider<AuthSession?>((
  Ref ref,
) {
  return AuthSession(
    serverUrl: Uri.parse('https://chat.example.test'),
    userId: 'me',
    username: 'me',
  );
});

final Provider<PostponedRepository> _postponedProvider =
    Provider<PostponedRepository>(
      (Ref ref) => const _NoopPostponedRepository(),
    );

final Map<
  InboxRepository,
  AsyncNotifierProvider<InboxController, InboxViewState>
>
_providers =
    <InboxRepository, AsyncNotifierProvider<InboxController, InboxViewState>>{};

AsyncNotifierProvider<InboxController, InboxViewState> _provider(
  InboxRepository repository,
) => _providers.putIfAbsent(repository, () {
  final Provider<InboxRepository> inboxProvider = Provider<InboxRepository>(
    (Ref ref) => repository,
  );
  return AsyncNotifierProvider.autoDispose<InboxController, InboxViewState>(
    () => InboxController(_sessionProvider, inboxProvider, _postponedProvider),
  );
});

ProviderContainer _container(InboxRepository repository) =>
    ProviderContainer()..listen(_provider(repository), (_, _) {});

InboxSnapshot _snapshot(String postId) => InboxSnapshot(
  newItems: <InboxItem>[
    ChannelPostInboxItem(
      candidate: InboxPostCandidate(
        post: Post(
          id: postId,
          channelId: 'channel',
          author: const PostAuthor(id: 'other', displayName: 'Other'),
          sentAt: DateTime.utc(2026),
          message: postId,
        ),
        channel: const SidebarChannel(
          id: 'channel',
          teamId: 'team',
          name: 'channel',
          displayName: 'Channel',
          kind: ChannelKind.publicChannel,
        ),
        reason: InboxAttentionReason.directMention,
      ),
    ),
  ],
);

final class _RefreshRepository extends InboxRepository {
  final Completer<void> firstRefreshStarted = Completer<void>();
  final Completer<void> firstRefreshCancelled = Completer<void>();
  final Completer<InboxSnapshot> secondRefresh = Completer<InboxSnapshot>();
  final Completer<InboxSnapshot> _firstRefresh = Completer<InboxSnapshot>();
  var _calls = 0;
  var firstRefreshWasCancelled = false;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) {
    _calls++;
    if (_calls == 1) return Future<InboxSnapshot>.value(_snapshot('initial'));
    if (_calls == 2) {
      firstRefreshStarted.complete();
      final RequestCancellation? cancellation = RequestCancellation.current;
      cancellation!.addListener((Object? reason) {
        firstRefreshWasCancelled = true;
        if (!firstRefreshCancelled.isCompleted) {
          firstRefreshCancelled.complete();
        }
        if (!_firstRefresh.isCompleted) {
          _firstRefresh.completeError(RequestCancelledException(reason));
        }
      });
      return _firstRefresh.future;
    }
    return secondRefresh.future;
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}
}

final class _SequenceRepository extends InboxRepository {
  _SequenceRepository(this._snapshots);

  final List<InboxSnapshot> _snapshots;
  var _index = 0;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async =>
      _snapshots[_index++];

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {}
}

final class _NoopPostponedRepository extends PostponedRepository {
  const _NoopPostponedRepository();

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
