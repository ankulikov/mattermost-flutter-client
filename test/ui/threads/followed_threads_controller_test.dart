import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/ui/threads/followed_threads_controller.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  test('pages from the last raw cursor and stops after a short page', () async {
    final _PagedThreadsRepository repository = _PagedThreadsRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWithValue(
          AuthSession(
            serverUrl: Uri.parse('https://chat.example.com'),
            userId: 'me',
            username: 'ada',
          ),
        ),
        threadRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final provider = followedThreadsProvider('team-1');
    final FollowedThreadsViewState initial = await container.read(
      provider.future,
    );
    expect(initial.items.map((FollowedThread item) => item.id), <String>[
      'root-1',
    ]);
    expect(initial.hasMore, isTrue);

    await container.read(provider.notifier).loadMore();
    final FollowedThreadsViewState loaded = container
        .read(provider)
        .requireValue;

    expect(repository.cursors, <String?>[null, 'raw-deleted-root']);
    expect(loaded.items.map((FollowedThread item) => item.id), <String>[
      'root-1',
      'root-2',
    ]);
    expect(loaded.hasMore, isFalse);
  });

  test('can page past a server page with no renderable threads', () async {
    final _PagedThreadsRepository repository = _PagedThreadsRepository(
      emptyFirstPage: true,
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWithValue(
          AuthSession(
            serverUrl: Uri.parse('https://chat.example.com'),
            userId: 'me',
            username: 'ada',
          ),
        ),
        threadRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final provider = followedThreadsProvider('team-1');
    final FollowedThreadsViewState initial = await container.read(
      provider.future,
    );
    expect(initial.items, isEmpty);
    expect(initial.hasMore, isTrue);

    await container.read(provider.notifier).loadMore();

    expect(container.read(provider).requireValue.items.single.id, 'root-2');
    expect(repository.cursors, <String?>[null, 'raw-deleted-root']);
  });

  test(
    'reloads unread totals when the followed-thread socket stream changes',
    () async {
      final _RealtimeThreadsRepository repository =
          _RealtimeThreadsRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWithValue(
            AuthSession(
              serverUrl: Uri.parse('https://chat.example.com'),
              userId: 'me',
              username: 'ada',
            ),
          ),
          threadRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final provider = followedThreadsProvider('team-1');
      final ProviderSubscription<AsyncValue<FollowedThreadsViewState>>
      listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      final FollowedThreadsViewState initial = await container.read(
        provider.future,
      );
      expect(initial.totalUnreadThreads, 1);

      repository.emitReadChanged();
      await _flush();

      expect(container.read(provider).requireValue.totalUnreadThreads, 0);
      expect(repository.loadCalls, 2);
    },
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _PagedThreadsRepository extends ThreadRepository {
  _PagedThreadsRepository({this.emptyFirstPage = false});

  final bool emptyFirstPage;
  final List<String?> cursors = <String?>[];

  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async {
    cursors.add(before);
    if (before == null) {
      return FollowedThreadsPage(
        items: emptyFirstPage
            ? const <FollowedThread>[]
            : <FollowedThread>[_thread('root-1')],
        total: 2,
        totalUnreadThreads: 1,
        totalUnreadMentions: 0,
        hasMore: true,
        nextBefore: 'raw-deleted-root',
      );
    }
    return FollowedThreadsPage(
      items: <FollowedThread>[_thread('root-2')],
      total: 2,
      totalUnreadThreads: 1,
      totalUnreadMentions: 0,
      hasMore: false,
      nextBefore: 'root-2',
    );
  }

  FollowedThread _thread(String id) => FollowedThread(
    root: ChannelPost(
      id: id,
      channelId: 'channel-1',
      author: const PostAuthor(id: 'author', displayName: 'Author'),
      sentAt: DateTime(2026, 10, 31),
      message: id,
    ),
    replyCount: 1,
    lastReplyAt: DateTime(2026, 10, 31),
    lastViewedAt: DateTime(2026, 10, 30),
    unreadReplies: id == 'root-1' ? 1 : 0,
    unreadMentions: 0,
  );
}

final class _RealtimeThreadsRepository extends ThreadRepository
    implements FollowedThreadsRealtimeRepository {
  final StreamController<FollowedThreadsRealtimeEvent> _events =
      StreamController<FollowedThreadsRealtimeEvent>.broadcast(sync: true);
  var loadCalls = 0;
  var _unread = true;

  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async {
    loadCalls += 1;
    return FollowedThreadsPage(
      items: <FollowedThread>[
        _thread('root-1', unreadReplies: _unread ? 1 : 0),
      ],
      total: 1,
      totalUnreadThreads: _unread ? 1 : 0,
      totalUnreadMentions: 0,
      hasMore: false,
    );
  }

  @override
  Stream<FollowedThreadsRealtimeEvent> watchFollowedThreads({
    required AuthSession session,
    required String teamId,
  }) => _events.stream;

  void emitReadChanged() {
    _unread = false;
    _events.add(const FollowedThreadsRefreshRequired());
  }

  Future<void> dispose() => _events.close();

  FollowedThread _thread(String id, {required int unreadReplies}) =>
      FollowedThread(
        root: ChannelPost(
          id: id,
          channelId: 'channel-1',
          author: const PostAuthor(id: 'author', displayName: 'Author'),
          sentAt: DateTime(2026, 10, 31),
          message: id,
        ),
        replyCount: 1,
        lastReplyAt: DateTime(2026, 10, 31),
        lastViewedAt: DateTime(2026, 10, 30),
        unreadReplies: unreadReplies,
        unreadMentions: 0,
      );
}
