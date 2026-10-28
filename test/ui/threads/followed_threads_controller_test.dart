import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_controller.dart';

void main() {
  test(
    'initial failure stays retryable through provider invalidation',
    () async {
      var calls = 0;
      final repository = _FakeRepository((_, _) async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return _page(<FollowedThread>[_thread('recovered')], total: 1);
      });
      final fixture = _fixture(repository);
      addTearDown(fixture.dispose);
      await expectLater(
        fixture.container.read(fixture.provider.future),
        throwsStateError,
      );
      expect(
        fixture.container.read(fixture.provider),
        isA<AsyncError<FollowedThreadsViewState>>(),
      );
      fixture.container.invalidate(fixture.provider);
      final recovered = await fixture.container.read(fixture.provider.future);
      expect(recovered.items.single.id, 'recovered');
    },
  );

  test('loads the first page and merges a cursor page by root ID', () async {
    final repository = _FakeRepository(
      (_, before) async => switch (before) {
        null => _page(<FollowedThread>[_thread('a'), _thread('b')], total: 3),
        _ => _page(<FollowedThread>[_thread('b'), _thread('c')], total: 3),
      },
    );
    final fixture = _fixture(repository);
    addTearDown(fixture.dispose);
    final initial = await fixture.container.read(fixture.provider.future);
    expect(initial.page, 0);
    expect(initial.hasMore, isTrue);
    await fixture.container.read(fixture.provider.notifier).loadMore();
    final result = fixture.container.read(fixture.provider).value!;
    expect(result.items.map((item) => item.id), <String>['a', 'b', 'c']);
    expect(result.page, 1);
    expect(result.hasMore, isFalse);
    expect(repository.calls, <(String, String?, int)>[
      ('team', null, 60),
      ('team', 'b', 60),
    ]);
  });

  test('empty next page completes even when total is stale', () async {
    final repository = _FakeRepository(
      (_, before) async => _page(
        before == null ? <FollowedThread>[_thread('a')] : <FollowedThread>[],
        total: 5,
      ),
    );
    final fixture = _fixture(repository);
    addTearDown(fixture.dispose);
    await fixture.container.read(fixture.provider.future);
    await fixture.container.read(fixture.provider.notifier).loadMore();
    final result = fixture.container.read(fixture.provider).value!;
    expect(result.items, hasLength(1));
    expect(result.paginationComplete, isTrue);
    expect(result.hasMore, isFalse);
  });

  test('repeated page retains rows and offers retry', () async {
    var attempts = 0;
    final repository = _FakeRepository((_, before) async {
      if (before == null) {
        return _page(<FollowedThread>[_thread('a')], total: 2);
      }
      attempts++;
      return _page(<FollowedThread>[
        _thread(attempts == 1 ? 'a' : 'b'),
      ], total: 2);
    });
    final fixture = _fixture(repository);
    addTearDown(fixture.dispose);
    await fixture.container.read(fixture.provider.future);
    await fixture.container.read(fixture.provider.notifier).loadMore();
    final failed = fixture.container.read(fixture.provider).value!;
    expect(failed.items.map((item) => item.id), <String>['a']);
    expect(failed.page, 0);
    expect(failed.paginationStatus, isA<OperationFailed>());
    expect(failed.hasMore, isTrue);
    await fixture.container.read(fixture.provider.notifier).loadMore();
    expect(fixture.container.read(fixture.provider).value!.items, hasLength(2));
  });

  test(
    'refresh keeps rows during work and on failure, then replaces them',
    () async {
      final refresh = Completer<FollowedThreadsPage>();
      var calls = 0;
      final repository = _FakeRepository((_, _) {
        calls++;
        if (calls == 1) {
          return Future.value(_page(<FollowedThread>[_thread('a')], total: 1));
        }
        if (calls == 2) return refresh.future;
        return Future.value(_page(<FollowedThread>[_thread('b')], total: 1));
      });
      final fixture = _fixture(repository);
      addTearDown(fixture.dispose);
      await fixture.container.read(fixture.provider.future);
      final pending = fixture.container
          .read(fixture.provider.notifier)
          .refresh();
      final loading = fixture.container.read(fixture.provider).value!;
      expect(loading.items.single.id, 'a');
      expect(loading.refreshStatus, isA<OperationInProgress>());
      refresh.completeError(StateError('offline'));
      await pending;
      final failed = fixture.container.read(fixture.provider).value!;
      expect(failed.items.single.id, 'a');
      expect(failed.refreshStatus, isA<OperationFailed>());
      await fixture.container.read(fixture.provider.notifier).refresh();
      expect(
        fixture.container.read(fixture.provider).value!.items.single.id,
        'b',
      );
    },
  );

  test(
    'read and unfollow reconcile counts without losing later replies',
    () async {
      final repository = _FakeRepository(
        (_, _) async => _page(
          <FollowedThread>[
            _thread('a', unreadReplies: 2, unreadMentions: 1),
            _thread('b', unreadReplies: 1),
          ],
          total: 2,
          unreadThreads: 2,
          unreadMentions: 1,
        ),
      );
      final fixture = _fixture(repository);
      addTearDown(fixture.dispose);
      await fixture.container.read(fixture.provider.future);
      final controller = fixture.container.read(fixture.provider.notifier);
      controller.recordThreadRead(
        rootPostId: 'a',
        timestamp: DateTime.fromMillisecondsSinceEpoch(500),
      );
      expect(
        fixture.container
            .read(fixture.provider)
            .value!
            .items
            .first
            .unreadReplies,
        2,
      );
      controller.recordThreadRead(
        rootPostId: 'a',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      var result = fixture.container.read(fixture.provider).value!;
      expect(result.items.first.unreadReplies, 0);
      expect(result.totalUnreadThreads, 1);
      expect(result.totalUnreadMentions, 0);
      controller.removeUnfollowedThread('b');
      result = fixture.container.read(fixture.provider).value!;
      expect(result.items.map((item) => item.id), <String>['a']);
      expect(result.total, 1);
      expect(result.totalUnreadThreads, 0);
    },
  );

  test('empty team does not request the repository', () async {
    final repository = _FakeRepository(
      (_, _) async => throw StateError('called'),
    );
    final fixture = _fixture(repository, teamId: '');
    addTearDown(fixture.dispose);
    final result = await fixture.container.read(fixture.provider.future);
    expect(result.items, isEmpty);
    expect(repository.calls, isEmpty);
  });

  test(
    'realtime refresh retains rows until the authoritative page arrives',
    () async {
      final signals = StreamController<void>.broadcast();
      addTearDown(signals.close);
      final refreshed = Completer<FollowedThreadsPage>();
      var calls = 0;
      final repository = _FakeRepository((_, _) {
        calls++;
        return calls == 1
            ? Future.value(_page(<FollowedThread>[_thread('old')], total: 1))
            : refreshed.future;
      }, signals: signals.stream);
      final fixture = _fixture(repository);
      addTearDown(fixture.dispose);
      await fixture.container.read(fixture.provider.future);
      signals.add(null);
      await Future<void>.delayed(Duration.zero);
      final loading = fixture.container.read(fixture.provider).value!;
      expect(loading.items.single.id, 'old');
      expect(loading.refreshStatus, isA<OperationInProgress>());
      refreshed.complete(_page(<FollowedThread>[_thread('new')], total: 1));
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.container.read(fixture.provider).value!.items.single.id,
        'new',
      );
    },
  );

  test('disposing the route cancels its in-flight list request', () async {
    final pending = Completer<FollowedThreadsPage>();
    RequestCancellation? observed;
    final repository = _FakeRepository((_, _) {
      observed = RequestCancellation.current;
      return pending.future;
    });
    final fixture = _fixture(repository);
    fixture.container.read(fixture.provider);
    expect(observed?.isCancelled, isFalse);
    fixture.dispose();
    expect(observed?.isCancelled, isTrue);
    pending.complete(_page(const <FollowedThread>[], total: 0));
  });
}

final class _Fixture {
  _Fixture(this.container, this.provider, this.subscription);
  final ProviderContainer container;
  final AsyncNotifierProvider<
    FollowedThreadsController,
    FollowedThreadsViewState
  >
  provider;
  final ProviderSubscription<AsyncValue<FollowedThreadsViewState>> subscription;
  void dispose() {
    subscription.close();
    container.dispose();
  }
}

_Fixture _fixture(_FakeRepository repository, {String teamId = 'team'}) {
  final sessionProvider = Provider<AuthSession?>(
    (ref) => AuthSession(
      serverUrl: Uri.parse('https://chat.example.com'),
      userId: 'me',
      username: 'me',
    ),
  );
  final repositoryProvider = Provider<ThreadRepository>((ref) => repository);
  final provider =
      AsyncNotifierProvider<
        FollowedThreadsController,
        FollowedThreadsViewState
      >(
        () => FollowedThreadsController(
          teamId,
          sessionProvider,
          repositoryProvider,
        ),
      );
  final container = ProviderContainer();
  return _Fixture(container, provider, container.listen(provider, (_, _) {}));
}

final class _FakeRepository extends ThreadRepository {
  _FakeRepository(this.handler, {this.signals});
  final Future<FollowedThreadsPage> Function(String teamId, String? before)
  handler;
  final Stream<void>? signals;
  final List<(String, String?, int)> calls = [];

  @override
  Stream<void> watchFollowed({
    required AuthSession session,
    required String teamId,
  }) => signals ?? const Stream<void>.empty();

  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
    int perPage = 60,
  }) {
    calls.add((teamId, before, perPage));
    return handler(teamId, before);
  }
}

FollowedThreadsPage _page(
  List<FollowedThread> items, {
  required int total,
  int unreadThreads = 0,
  int unreadMentions = 0,
}) => FollowedThreadsPage(
  items: items,
  total: total,
  totalUnreadThreads: unreadThreads,
  totalUnreadMentions: unreadMentions,
);

FollowedThread _thread(
  String id, {
  int unreadReplies = 0,
  int unreadMentions = 0,
}) => FollowedThread(
  root: Post(
    id: id,
    channelId: 'channel',
    author: const PostAuthor(id: 'author', displayName: 'Ada'),
    sentAt: DateTime.fromMillisecondsSinceEpoch(100),
    message: id,
  ),
  replyCount: 2,
  lastReplyAt: DateTime.fromMillisecondsSinceEpoch(1000),
  lastViewedAt: DateTime.fromMillisecondsSinceEpoch(100),
  unreadReplies: unreadReplies,
  unreadMentions: unreadMentions,
);
