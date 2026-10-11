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

  test(
    'mark read removes every non-thread item in the viewed channel',
    () async {
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
      expect(container.read(provider).value?.snapshot.newItems, isEmpty);
    },
  );

  test(
    'marks roots individually until the final root advances the channel',
    () async {
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

      expect(repository.individuallyViewed, same(first));
      expect(repository.markedRead, isNull);
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.key,
        second.key,
      );

      expect(await container.read(provider.notifier).markRead(second), isTrue);

      expect(repository.markedRead, same(second));
      expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);
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
    )..markPostViewedGate = viewed;
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await _waitForInitialLoad(container, provider);

    final Future<bool> request = container
        .read(provider.notifier)
        .markRead(first);
    await _waitUntil(() => repository.individuallyViewed != null);
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

  test(
    'the final ordinary channel root advances the channel boundary',
    () async {
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
      expect(repository.individuallyViewed, isNull);
      expect(container.read(provider).requireValue.snapshot.newItems, isEmpty);
    },
  );

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

      expect(repository.markedThreadRead, same(thread));
      expect(repository.preservedOtherChannelRoots, isTrue);
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

ThreadInboxItem _threadItem() {
  final InboxPostCandidate root = _candidate('thread-root', direct: false);
  return ThreadInboxItem(
    thread: FollowedThread(
      root: root.post,
      replyCount: 1,
      lastReplyAt: DateTime.utc(2026, 1, 2),
      lastViewedAt: DateTime.utc(2026),
      unreadReplies: 1,
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
  ThreadInboxItem? markedThreadRead;
  bool? preservedOtherChannelRoots;
  ChannelPostInboxItem? individuallyViewed;
  Completer<void>? markPostViewedGate;

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
  }

  @override
  Future<void> markThreadRead({
    required AuthSession session,
    required ThreadInboxItem item,
    required bool preserveOtherChannelRoots,
  }) async {
    markedThreadRead = item;
    preservedOtherChannelRoots = preserveOtherChannelRoots;
  }

  @override
  Future<void> markPostViewed({
    required AuthSession session,
    required ChannelPostInboxItem item,
  }) async {
    individuallyViewed = item;
    await markPostViewedGate?.future;
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
    saved = List<PostponedReference>.of(references);
  }
}
