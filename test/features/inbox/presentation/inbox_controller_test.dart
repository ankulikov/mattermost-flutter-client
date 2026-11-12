import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_counters.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';

void main() {
  test(
    'uses persisted counters while loading and retains the loaded snapshot',
    () async {
      final Completer<InboxSnapshot> loaded = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[() => loaded.future],
        storedCounters: const InboxCounters(
          newMessages: 4,
          postponedMessages: 2,
        ),
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);

      final InboxViewState cached = await container.read(provider.future);
      expect(cached.hasLoadedSnapshot, isFalse);
      expect(cached.newMessageCount, 4);
      expect(cached.postponedMessageCount, 2);
      await _waitUntil(() => repository.loadCalls == 1);

      loaded.complete(
        InboxSnapshot(
          newItems: <InboxItem>[
            ChannelPostInboxItem(candidate: _candidate('fresh')),
          ],
        ),
      );
      await _waitForInitialLoad(container, provider);

      expect(container.read(provider).requireValue.newMessageCount, 1);
      await _waitUntil(() => repository.savedCounters.isNotEmpty);
      expect(repository.savedCounters.last.newMessages, 1);

      await container.read(provider.notifier).retryInitialLoad();
      expect(repository.loadCalls, 1);
    },
  );

  test('merges realtime posts and tracks connection state', () async {
    final StreamController<InboxRealtimeEvent> realtime =
        StreamController<InboxRealtimeEvent>();
    addTearDown(realtime.close);
    final InboxPostCandidate first = _candidate('first');
    final InboxPostCandidate second = _candidate('second');
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(
          newItems: <InboxItem>[
            DirectMessageBundleInboxItem(
              channelId: 'channel',
              authorId: 'other',
              automationClass: InboxAutomationClass.person,
              messages: <InboxPostCandidate>[first],
            ),
          ],
        ),
      ],
      realtime: realtime.stream,
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    realtime.add(const InboxConnectionChanged(InboxConnectionStatus.connected));
    realtime.add(InboxPostChanged(postId: second.post.id, candidate: second));
    await Future<void>.delayed(Duration.zero);

    final InboxInAppNotification? notification = container
        .read(provider)
        .requireValue
        .inAppNotification;
    expect(notification?.id, 'second');

    realtime.add(InboxPostChanged(postId: second.post.id, candidate: second));
    await Future<void>.delayed(Duration.zero);

    final InboxViewState state = container.read(provider).requireValue;
    expect(state.connectionStatus, InboxConnectionStatus.connected);
    expect(state.snapshot.newItems, hasLength(1));
    expect(state.snapshot.newItems.single.postIds, <String>['first', 'second']);
    expect(state.inAppNotification, same(notification));
    expect(repository.loadCalls, 1);
  });

  test('resume reconnects realtime and reconciles missed events', () async {
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(),
        () async => InboxSnapshot(
          newItems: <InboxItem>[
            ChannelPostInboxItem(candidate: _candidate('missed')),
          ],
        ),
      ],
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    container.read(provider.notifier).handleAppResumed();
    await _waitUntil(() => repository.loadCalls == 2);
    await Future<void>.delayed(Duration.zero);

    expect(repository.reconnectCalls, 1);
    expect(
      container.read(provider).requireValue.snapshot.newItems.single.postIds,
      <String>['missed'],
    );
    expect(container.read(provider).requireValue.inAppNotification, isNull);
  });

  test(
    'a realtime recovery request refreshes without dropping old data',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> refreshed = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old')),
            ],
          ),
          () => refreshed.future,
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await _waitForInitialLoad(container, provider);

      realtime.add(const InboxRefreshRequired());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(provider).requireValue.refreshStatus,
        isA<OperationInProgress>(),
      );
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.postIds,
        <String>['old'],
      );

      final InboxPostCandidate duringRefresh = _candidate('during-refresh');
      realtime.add(
        InboxPostChanged(
          postId: duringRefresh.post.id,
          candidate: duringRefresh,
        ),
      );

      refreshed.complete(
        InboxSnapshot(
          newItems: <InboxItem>[
            ChannelPostInboxItem(candidate: _candidate('fresh')),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(provider)
            .requireValue
            .snapshot
            .newItems
            .expand((InboxItem item) => item.postIds),
        containsAll(<String>['fresh', 'during-refresh']),
      );
      expect(repository.loadCalls, 2);
    },
  );

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
      await _waitForInitialLoad(container, provider);
      final InboxViewState initial = container.read(provider).requireValue;
      expect(initial.refreshStatus, isA<OperationIdle>());

      final Future<void> request = container.read(provider.notifier).refresh();
      expect(
        container.read(provider).value?.refreshStatus,
        isA<OperationInProgress>(),
      );
      refresh.complete(InboxSnapshot());
      await request;
      expect(
        container.read(provider).value?.refreshStatus,
        isA<OperationIdle>(),
      );
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
      await _waitForInitialLoad(container, provider);
      await container.read(provider.notifier).refresh();
      expect(container.read(provider).hasValue, isTrue);
      expect(
        container.read(provider).value?.refreshStatus,
        isA<OperationFailed>(),
      );
    },
  );

  test('mark read preserves other posts in the same channel', () async {
    final InboxPostCandidate first = _candidate('first');
    final InboxPostCandidate second = _candidate('second');
    final DirectMessageBundleInboxItem bundle = DirectMessageBundleInboxItem(
      channelId: 'channel',
      authorId: 'other',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[first, second],
    );
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(
          newItems: <InboxItem>[
            bundle,
            ChannelPostInboxItem(candidate: _candidate('third')),
          ],
        ),
      ],
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    expect(await container.read(provider.notifier).markRead(bundle), isTrue);

    expect(repository.markedRead, same(bundle));
    expect(
      container.read(provider).value?.snapshot.newItems.single.postIds,
      <String>['third'],
    );
  });

  test('marks roots individually including the final root', () async {
    final ChannelPostInboxItem first = ChannelPostInboxItem(
      candidate: _candidate('first', direct: false),
    );
    final ChannelPostInboxItem second = ChannelPostInboxItem(
      candidate: _candidate('second', direct: false),
    );
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(newItems: <InboxItem>[first, second]),
      ],
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    expect(await container.read(provider.notifier).markRead(first), isTrue);

    expect(repository.markedRead, same(first));
    expect(
      container.read(provider).requireValue.snapshot.newItems.single.key,
      second.key,
    );

    expect(await container.read(provider.notifier).markRead(second), isTrue);

    expect(repository.markedRead, same(second));
    expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);
  });

  test(
    'Done during refresh preserves new messages in the same bundle',
    () async {
      final Completer<InboxSnapshot> refresh = Completer<InboxSnapshot>();
      final InboxPostCandidate first = _candidate('first');
      final InboxPostCandidate second = _candidate('second');
      DirectMessageBundleInboxItem bundle(List<InboxPostCandidate> messages) =>
          DirectMessageBundleInboxItem(
            channelId: 'channel',
            authorId: 'other',
            automationClass: InboxAutomationClass.person,
            messages: messages,
          );
      final InboxItem tapped = bundle(<InboxPostCandidate>[first]);
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[tapped]),
          () => refresh.future,
        ],
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await _waitForInitialLoad(container, provider);

      final InboxController controller = container.read(provider.notifier);
      final Future<void> refreshing = controller.refresh();
      final Future<bool> done = controller.markRead(tapped);
      expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);
      expect(repository.markedRead, isNull);

      refresh.complete(
        InboxSnapshot(
          newItems: <InboxItem>[
            bundle(<InboxPostCandidate>[first, second]),
          ],
        ),
      );
      await refreshing;
      expect(await done, isTrue);
      expect(repository.markedRead, same(tapped));
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.postIds,
        <String>['second'],
      );
    },
  );

  test('Done keeps newer replies and refreshes their unread count', () async {
    final Completer<InboxSnapshot> refresh = Completer<InboxSnapshot>();
    final Completer<InboxSnapshot> readback = Completer<InboxSnapshot>();
    final ThreadInboxItem tapped = _threadItem();
    final ThreadInboxItem newer = _threadItem(
      lastReplyAt: DateTime.utc(2026, 1, 3),
      unreadReplies: 2,
    );
    final ThreadInboxItem reconciled = _threadItem(
      lastReplyAt: newer.thread.lastReplyAt,
      lastViewedAt: tapped.thread.lastReplyAt,
    );
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(newItems: <InboxItem>[tapped]),
        () => refresh.future,
        () => readback.future,
      ],
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    final InboxController controller = container.read(provider.notifier);
    final Future<void> refreshing = controller.refresh();
    final Future<bool> done = controller.markRead(tapped);
    expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);

    refresh.complete(InboxSnapshot(newItems: <InboxItem>[newer]));
    await refreshing;
    expect(await done, isTrue);
    expect(repository.markedRead, same(tapped));
    expect(
      container.read(provider).requireValue.snapshot.newItems.single,
      same(newer),
    );
    expect(
      container
          .read(provider)
          .requireValue
          .isThreadReadPending(newer.thread.id),
      isTrue,
    );

    readback.complete(InboxSnapshot(newItems: <InboxItem>[reconciled]));
    await _waitUntil(
      () => !container
          .read(provider)
          .requireValue
          .isThreadReadPending(newer.thread.id),
    );
    expect(
      container.read(provider).requireValue.snapshot.newItems.single,
      same(reconciled),
    );
  });

  test(
    'failed Done restores unread items and reports an Inbox failure',
    () async {
      final InboxItem item = ChannelPostInboxItem(
        candidate: _candidate('first'),
      );
      final Completer<void> write = Completer<void>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[item]),
        ],
      )..markReadGate = write;
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await _waitForInitialLoad(container, provider);

      final Future<bool> done = container
          .read(provider.notifier)
          .markRead(item);
      expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);
      write.completeError(StateError('write failed'));
      expect(await done, isFalse);
      final InboxViewState state = container.read(provider).requireValue;
      expect(state.snapshot.newItems.single, same(item));
      expect(state.readFailureCount, 1);
    },
  );

  test('queued edits cannot restore an individually viewed root', () async {
    final StreamController<InboxRealtimeEvent> realtime =
        StreamController<InboxRealtimeEvent>();
    addTearDown(realtime.close);
    final ChannelPostInboxItem first = ChannelPostInboxItem(
      candidate: _candidate('first', direct: false),
    );
    final ChannelPostInboxItem second = ChannelPostInboxItem(
      candidate: _candidate('second', direct: false),
    );
    final Completer<void> viewed = Completer<void>();
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(newItems: <InboxItem>[first, second]),
      ],
      realtime: realtime.stream,
    )..markReadGate = viewed;
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    final Future<bool> request = container
        .read(provider.notifier)
        .markRead(first);
    await _waitUntil(() => repository.markedRead != null);
    realtime.add(
      InboxPostChanged(postId: first.post.id, candidate: first.candidate),
    );
    await Future<void>.delayed(Duration.zero);
    viewed.complete();

    expect(await request, isTrue);
    expect(
      container.read(provider).requireValue.snapshot.newItems.single.key,
      second.key,
    );
  });

  test('the final ordinary channel root is acknowledged by ID', () async {
    final ChannelPostInboxItem only = ChannelPostInboxItem(
      candidate: _candidate('only', direct: false),
    );
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(newItems: <InboxItem>[only]),
      ],
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    expect(await container.read(provider.notifier).markRead(only), isTrue);

    expect(repository.markedRead, same(only));
    expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);
  });

  test(
    'marking a thread read preserves other roots and suppresses its root',
    () async {
      final ThreadInboxItem thread = _threadItem();
      final ChannelPostInboxItem otherRoot = ChannelPostInboxItem(
        candidate: _candidate('other-root', direct: false),
      );
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[thread, otherRoot]),
        ],
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await _waitForInitialLoad(container, provider);

      expect(await container.read(provider.notifier).markRead(thread), isTrue);

      expect(repository.markedRead, same(thread));
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.key,
        otherRoot.key,
      );
    },
  );

  test('postponing a DM bundle moves only its latest message', () async {
    final InboxPostCandidate first = _candidate('first');
    final InboxPostCandidate second = _candidate('second');
    final DirectMessageBundleInboxItem bundle = DirectMessageBundleInboxItem(
      channelId: 'channel',
      authorId: 'other',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[first, second],
    );
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(newItems: <InboxItem>[bundle]),
      ],
    );
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository();
    final provider = _provider(repository, postponed: postponed);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);
    expect(await container.read(provider.notifier).postpone(bundle), isTrue);

    final InboxSnapshot snapshot = container.read(provider).value!.snapshot;
    expect(snapshot.newItems.single.postIds, <String>['first']);
    expect(snapshot.postponedItems.single.postIds, <String>['second']);
    expect(postponed.saved.single.postId, 'second');
  });

  test('postpones an arbitrary reply directly into the queue', () async {
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository();
    final provider = _provider(
      _InboxRepository(<Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(),
      ]),
      postponed: postponed,
    );
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);
    final InboxPostCandidate source = _candidate('reply');
    final Post reply = Post(
      id: source.post.id,
      rootId: 'root',
      channelId: source.post.channelId,
      author: source.post.author,
      sentAt: source.post.sentAt,
      message: source.post.message,
    );

    expect(
      await container
          .read(provider.notifier)
          .postponeMessage(post: reply, channel: source.channel),
      isTrue,
    );

    expect(postponed.saved.single.postId, 'reply');
    expect(postponed.saved.single.kind, PostponedReferenceKind.post);
    final InboxSnapshot snapshot = container
        .read(provider)
        .requireValue
        .snapshot;
    expect(snapshot.postponedItems.single.postIds, <String>['reply']);
    expect(snapshot.newItems, isEmpty);
  });

  test('postpones a New message without leaving it in both queues', () async {
    final InboxPostCandidate source = _candidate('selected');
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository();
    final provider = _provider(
      _InboxRepository(<Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(
          newItems: <InboxItem>[ChannelPostInboxItem(candidate: source)],
        ),
      ]),
      postponed: postponed,
    );
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    expect(
      await container
          .read(provider.notifier)
          .postponeMessage(post: source.post, channel: source.channel),
      isTrue,
    );

    final InboxSnapshot snapshot = container
        .read(provider)
        .requireValue
        .snapshot;
    expect(snapshot.newItems, isEmpty);
    expect(snapshot.postponedItems.single.postIds, <String>['selected']);
  });

  test('reconciles a message postponed during initial loading', () async {
    final Completer<InboxSnapshot> firstLoad = Completer<InboxSnapshot>();
    final InboxPostCandidate source = _candidate('selected');
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () => firstLoad.future,
        () async => InboxSnapshot(
          postponedItems: <InboxItem>[ChannelPostInboxItem(candidate: source)],
        ),
      ],
    );
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository();
    final provider = _provider(repository, postponed: postponed);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await container.read(provider.future);
    await _waitUntil(() => repository.loadCalls == 1);

    expect(
      await container
          .read(provider.notifier)
          .postponeMessage(post: source.post, channel: source.channel),
      isTrue,
    );
    firstLoad.complete(InboxSnapshot());
    await _waitUntil(() => repository.loadCalls == 2);
    await _waitUntil(
      () => container.read(provider).value?.snapshot.postponedItems.length == 1,
    );

    expect(postponed.saved.single.postId, 'selected');
    expect(container.read(provider).requireValue.postponedMessageCount, 1);
  });

  test('failed message postponement leaves the queue unchanged', () async {
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository()..failSave = true;
    final InboxPostCandidate source = _candidate('new');
    final provider = _provider(
      _InboxRepository(<Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(
          newItems: <InboxItem>[ChannelPostInboxItem(candidate: source)],
        ),
      ]),
      postponed: postponed,
    );
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    expect(
      await container
          .read(provider.notifier)
          .postponeMessage(post: source.post, channel: source.channel),
      isFalse,
    );

    final InboxSnapshot snapshot = container
        .read(provider)
        .requireValue
        .snapshot;
    expect(snapshot.newItems.single.postIds, <String>['new']);
    expect(snapshot.postponedItems, isEmpty);
  });
}

InboxPostCandidate _candidate(String id, {bool direct = true}) =>
    InboxPostCandidate(
      post: Post(
        id: id,
        channelId: 'channel',
        author: const PostAuthor(id: 'other', displayName: 'Other'),
        sentAt: DateTime.utc(2026),
        message: id,
      ),
      channel: SidebarChannel(
        id: 'channel',
        teamId: 'team',
        name: 'channel',
        displayName: 'Channel',
        kind: direct ? ChannelKind.directMessage : ChannelKind.publicChannel,
      ),
      reason: InboxAttentionReason.allMessagesSubscription,
    );

ThreadInboxItem _threadItem({
  DateTime? lastReplyAt,
  DateTime? lastViewedAt,
  int unreadReplies = 1,
}) {
  final InboxPostCandidate root = _candidate('thread-root', direct: false);
  return ThreadInboxItem(
    thread: FollowedThread(
      root: root.post,
      replyCount: 2,
      lastReplyAt: lastReplyAt ?? DateTime.utc(2026, 1, 2),
      lastViewedAt: lastViewedAt ?? DateTime.utc(2026),
      unreadReplies: unreadReplies,
      unreadMentions: 0,
    ),
    channel: root.channel,
    teamId: 'team',
    rootAttentionReason: InboxAttentionReason.directMention,
  );
}

AsyncNotifierProvider<InboxController, InboxViewState> _provider(
  InboxRepository repository, {
  PostponedRepository postponed = const _PostponedRepository(),
}) {
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
      Provider<PostponedRepository>((Ref ref) => postponed);
  return AsyncNotifierProvider.autoDispose<InboxController, InboxViewState>(
    () => InboxController(sessionProvider, inboxProvider, postponedProvider),
  );
}

final class _InboxRepository extends InboxRepository {
  _InboxRepository(
    this.results, {
    this.realtime = const Stream<InboxRealtimeEvent>.empty(),
    this.storedCounters = InboxCounters.empty,
  });
  final List<Future<InboxSnapshot> Function()> results;
  final Stream<InboxRealtimeEvent> realtime;
  final InboxCounters storedCounters;
  final List<InboxCounters> savedCounters = <InboxCounters>[];
  var _index = 0;
  var loadCalls = 0;
  var reconnectCalls = 0;
  InboxItem? markedRead;
  Completer<void>? markReadGate;

  @override
  Future<InboxCounters> loadCounters({required AuthSession session}) async =>
      storedCounters;

  @override
  Future<void> saveCounters({
    required AuthSession session,
    required InboxCounters counters,
  }) async => savedCounters.add(counters);

  @override
  Future<InboxSnapshot> load({required AuthSession session}) {
    loadCalls++;
    return results[_index++]();
  }

  @override
  Stream<InboxRealtimeEvent> watch({required AuthSession session}) => realtime;

  @override
  void reconnectRealtime() => reconnectCalls++;

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) async {
    markedRead = item;
    await markReadGate?.future;
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

Future<void> _waitForInitialLoad(
  ProviderContainer container,
  AsyncNotifierProvider<InboxController, InboxViewState> provider,
) async {
  await container.read(provider.future);
  await _waitUntil(
    () => container.read(provider).value?.hasLoadedSnapshot == true,
  );
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

final class _RecordingPostponedRepository extends PostponedRepository {
  List<PostponedReference> saved = <PostponedReference>[];
  bool failSave = false;

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
  }) async {
    if (failSave) throw StateError('Preference write failed');
    saved = List<PostponedReference>.of(references);
  }
}
