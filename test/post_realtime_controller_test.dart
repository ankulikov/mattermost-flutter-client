import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/ui/posts/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_controller.dart';

void main() {
  group('open channel realtime', () {
    test('reconciles events that race the initial REST response', () async {
      final Completer<ChannelPostPage> load = Completer<ChannelPostPage>();
      final _RealtimePostRepository posts = _RealtimePostRepository(
        loads: <Future<ChannelPostPage> Function()>[() => load.future],
      );
      final (:container, :provider) = _channelContainer(posts);
      final Future<ChannelPostsViewState> ready = container.read(
        provider.future,
      );
      await _waitUntil(() => posts.hasListener);

      posts.add(
        PostRealtimeUpserted(_post('post-1', 'event edit', revision: 3)),
      );
      posts.add(PostRealtimeUpserted(_post('post-2', 'new', revision: 4)));
      load.complete(
        ChannelPostPage(
          posts: <ChannelPost>[_post('post-1', 'newer REST edit', revision: 5)],
        ),
      );

      await ready;
      await _waitUntil(() => container.read(provider).value?.posts.length == 2);
      final List<ChannelPost> visible = container
          .read(provider)
          .requireValue
          .posts;
      expect(visible.map((ChannelPost post) => post.id).toSet(), <String>{
        'post-1',
        'post-2',
      });
      expect(
        visible.singleWhere((ChannelPost post) => post.id == 'post-1').message,
        'newer REST edit',
      );

      container.dispose();
      await _waitUntil(() => posts.wasCancelled);
    });

    test('adds, edits, and removes roots and reply summaries', () async {
      final _RealtimePostRepository posts = _RealtimePostRepository(
        loads: <Future<ChannelPostPage> Function()>[
          () async => ChannelPostPage(
            posts: <ChannelPost>[_post('root', 'root', replyCount: 0)],
          ),
        ],
      );
      final (:container, :provider) = _channelContainer(posts);
      addTearDown(container.dispose);
      await container.read(provider.future);

      final ChannelPost reply = _post(
        'reply',
        'reply',
        rootId: 'root',
        revision: 2,
      );
      posts.add(PostRealtimeUpserted(reply));
      await _waitUntil(
        () => container.read(provider).value?.posts.single.replyCount == 1,
      );
      expect(
        container.read(provider).requireValue.replySummaries['root']?.replyIds,
        <String>{'reply'},
      );

      posts.add(PostRealtimeUpserted(_post('root', 'edited', revision: 3)));
      await _waitUntil(
        () => container.read(provider).value?.posts.single.message == 'edited',
      );

      posts.add(PostRealtimeDeleted(_deleted(reply, revision: 4)));
      await _waitUntil(
        () => container.read(provider).value?.posts.single.replyCount == 0,
      );
      expect(
        container.read(provider).requireValue.replySummaries['root']?.replyIds,
        isEmpty,
      );

      posts.add(
        PostRealtimeDeleted(
          _deleted(container.read(provider).requireValue.posts.single),
        ),
      );
      await _waitUntil(
        () => container.read(provider).value?.posts.isEmpty == true,
      );
    });

    test('keeps live events received during gap recovery', () async {
      final Completer<ChannelPostPage> recovery = Completer<ChannelPostPage>();
      final _RealtimePostRepository posts = _RealtimePostRepository(
        loads: <Future<ChannelPostPage> Function()>[
          () async =>
              ChannelPostPage(posts: <ChannelPost>[_post('root', 'initial')]),
          () => recovery.future,
        ],
      );
      final (:container, :provider) = _channelContainer(posts);
      addTearDown(container.dispose);
      await container.read(provider.future);

      posts.add(const PostRealtimeRecoveryRequired());
      await _waitUntil(() => posts.loadCalls == 2);
      expect(container.read(provider).requireValue.posts.single.id, 'root');

      posts.add(PostRealtimeUpserted(_post('live', 'during recovery')));
      recovery.complete(
        ChannelPostPage(posts: <ChannelPost>[_post('root', 'recovered')]),
      );
      await _waitUntil(() => container.read(provider).value?.posts.length == 2);
      expect(
        container
            .read(provider)
            .requireValue
            .posts
            .map((post) => post.id)
            .toSet(),
        <String>{'root', 'live'},
      );
    });
  });

  test('open thread adds, edits, and removes matching replies', () async {
    final ChannelPost root = _post('root', 'root', replyCount: 1);
    final ChannelPost existing = _post('existing', 'existing', rootId: 'root');
    final _RealtimePostRepository posts = _RealtimePostRepository();
    final _ThreadRepository threads = _ThreadRepository(
      MessageThread(
        rootPostId: 'root',
        root: root,
        replies: <ChannelPost>[existing],
        isComplete: true,
        loadedAt: DateTime.fromMillisecondsSinceEpoch(10),
      ),
    );
    final (:container, :provider) = _threadContainer(posts, threads);
    addTearDown(container.dispose);
    await container.read(provider.future);
    await _waitUntil(() => posts.hasListener, reason: 'thread subscription');

    posts.add(
      PostRealtimeUpserted(
        _post('new-reply', 'new', rootId: 'root', revision: 2),
      ),
    );
    await _waitUntil(
      () => container.read(provider).value?.thread.replies.length == 2,
      reason: 'new thread reply',
    );
    expect(container.read(provider).requireValue.thread.root?.replyCount, 2);

    posts.add(
      PostRealtimeUpserted(
        _post('existing', 'edited', rootId: 'root', revision: 3),
      ),
    );
    await _waitUntil(
      () =>
          container
              .read(provider)
              .value
              ?.thread
              .replies
              .where((ChannelPost post) => post.id == 'existing')
              .single
              .message ==
          'edited',
      reason: 'edited thread reply',
    );

    posts.add(PostRealtimeDeleted(_deleted(existing, revision: 4)));
    await _waitUntil(
      () => container.read(provider).value?.thread.replies.length == 1,
      reason: 'deleted thread reply',
    );
    expect(
      container.read(provider).requireValue.thread.replies.single.id,
      'new-reply',
    );
    expect(container.read(provider).requireValue.thread.root?.replyCount, 1);

    posts.add(PostRealtimeDeleted(_deleted(existing, revision: 4)));
    await pumpEventQueue();
    expect(container.read(provider).requireValue.thread.replies, hasLength(1));
    expect(container.read(provider).requireValue.thread.root?.replyCount, 1);

    posts.add(
      PostRealtimeUpserted(
        _post('other-reply', 'other', rootId: 'another-root'),
      ),
    );
    await pumpEventQueue();
    expect(container.read(provider).requireValue.thread.replies, hasLength(1));
  });
}

({
  ProviderContainer container,
  AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState> provider,
})
_channelContainer(PostRepository posts) {
  final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>(
    (_) => _session,
  );
  final Provider<PostRepository> postsProvider = Provider<PostRepository>(
    (_) => posts,
  );
  final provider =
      AsyncNotifierProvider<ChannelPostsController, ChannelPostsViewState>(
        () =>
            ChannelPostsController('channel-1', sessionProvider, postsProvider),
      );
  return (container: ProviderContainer(), provider: provider);
}

({
  ProviderContainer container,
  AsyncNotifierProvider<ThreadController, ThreadViewState> provider,
})
_threadContainer(PostRepository posts, ThreadRepository threads) {
  final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>(
    (_) => _session,
  );
  final Provider<PostRepository> postsProvider = Provider<PostRepository>(
    (_) => posts,
  );
  final Provider<ThreadRepository> threadsProvider = Provider<ThreadRepository>(
    (_) => threads,
  );
  final Provider<PostponedRepository> postponedProvider =
      Provider<PostponedRepository>((_) => const _PostponedRepository());
  final provider = AsyncNotifierProvider<ThreadController, ThreadViewState>(
    () => ThreadController(
      'root',
      sessionProvider,
      threadsProvider,
      postsProvider,
      postponedProvider,
      'team-1',
      false,
    ),
  );
  return (container: ProviderContainer(), provider: provider);
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.com'),
  userId: 'me',
  username: 'current',
);

ChannelPost _post(
  String id,
  String message, {
  String rootId = '',
  int replyCount = 0,
  int revision = 1,
}) => ChannelPost(
  id: id,
  channelId: 'channel-1',
  author: const PostAuthor(id: 'ada', displayName: 'Ada'),
  sentAt: DateTime.fromMillisecondsSinceEpoch(revision),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(revision),
  message: message,
  rootId: rootId,
  replyCount: replyCount,
);

ChannelPost _deleted(ChannelPost post, {int revision = 10}) => ChannelPost(
  id: post.id,
  channelId: post.channelId,
  author: post.author,
  sentAt: post.sentAt,
  updatedAt: DateTime.fromMillisecondsSinceEpoch(revision),
  message: '',
  rootId: post.rootId,
  isDeleted: true,
);

Future<void> _waitUntil(
  bool Function() condition, {
  String reason = 'condition',
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('$reason was not reached');
}

final class _RealtimePostRepository extends PostRepository {
  _RealtimePostRepository({
    this.loads = const <Future<ChannelPostPage> Function()>[],
  });

  final List<Future<ChannelPostPage> Function()> loads;
  late final StreamController<PostRealtimeEvent> _events =
      StreamController<PostRealtimeEvent>.broadcast(
        onListen: () => hasListener = true,
        onCancel: () => wasCancelled = true,
      );
  int loadCalls = 0;
  bool hasListener = false;
  bool wasCancelled = false;

  void add(PostRealtimeEvent event) => _events.add(event);

  @override
  Stream<PostRealtimeEvent> watchRealtime({
    required AuthSession session,
    String channelId = '',
    String rootPostId = '',
  }) => _events.stream;

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) {
    final int index = loadCalls;
    loadCalls += 1;
    return loads[index]();
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();
}

final class _ThreadRepository extends ThreadRepository {
  const _ThreadRepository(this.thread);

  final MessageThread thread;

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async => thread;
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
