import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/use_cases/postpone_thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/use_cases/reactivate_postponed_thread.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_controller.dart';

void main() {
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
    final Provider<InboxInAppNotificationEvents> eventsProvider =
        _notificationEventsProvider();
    final provider = _provider(
      repository,
      inAppNotificationEventsProvider: eventsProvider,
    );
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    final List<InboxInAppNotification> notifications =
        <InboxInAppNotification>[];
    final StreamSubscription<InboxInAppNotification> subscription = container
        .read(eventsProvider)
        .stream
        .listen(notifications.add);
    addTearDown(subscription.cancel);
    await container.read(provider.future);

    realtime.add(const InboxConnectionChanged(InboxConnectionStatus.connected));
    realtime.add(InboxPostChanged(postId: second.post.id, candidate: second));
    await Future<void>.delayed(Duration.zero);

    await _waitUntil(() => notifications.length == 1);
    expect(notifications.single.id, 'second');
    expect(notifications.single.messagePreview, isNull);

    realtime.add(InboxPostChanged(postId: second.post.id, candidate: second));
    await Future<void>.delayed(Duration.zero);

    final InboxViewState state = container.read(provider).requireValue;
    expect(state.connectionStatus, InboxConnectionStatus.connected);
    expect(state.snapshot.newItems, hasLength(1));
    expect(state.snapshot.newItems.single.postIds, <String>['first', 'second']);
    expect(notifications, hasLength(1));
    expect(repository.loadCalls, 1);
  });

  test('includes a foreground preview only after the user opts in', () async {
    final StreamController<InboxRealtimeEvent> realtime =
        StreamController<InboxRealtimeEvent>();
    addTearDown(realtime.close);
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[() async => InboxSnapshot()],
      realtime: realtime.stream,
    );
    final Provider<InboxInAppNotificationEvents> eventsProvider =
        _notificationEventsProvider();
    final provider = _provider(
      repository,
      settings: const _SettingsRepository(
        InboxSettings(
          inAppNotification: InboxInAppNotificationSettings(
            showMessagePreview: true,
          ),
        ),
      ),
      inAppNotificationEventsProvider: eventsProvider,
    );
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    final List<InboxInAppNotification> notifications =
        <InboxInAppNotification>[];
    final StreamSubscription<InboxInAppNotification> subscription = container
        .read(eventsProvider)
        .stream
        .listen(notifications.add);
    addTearDown(subscription.cancel);
    await container.read(provider.future);

    realtime.add(
      InboxPostChanged(
        postId: 'private',
        candidate: _candidate('private', message: 'Private server message'),
      ),
    );
    await _waitUntil(() => notifications.isNotEmpty);

    expect(notifications.single.messagePreview, 'Private server message');
  });

  test(
    'keeps a shell event stream across a session rebuild without replaying refresh or duplicate events',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>.broadcast();
      addTearDown(realtime.close);
      final InboxPostCandidate first = _candidate('first');
      final InboxPostCandidate second = _candidate('second');
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(),
          () async => InboxSnapshot(
            newItems: <InboxItem>[ChannelPostInboxItem(candidate: first)],
          ),
          () async => InboxSnapshot(
            newItems: <InboxItem>[ChannelPostInboxItem(candidate: first)],
          ),
        ],
        realtime: realtime.stream,
      );
      final NotifierProvider<_MutableSession, AuthSession?> sessionState =
          NotifierProvider<_MutableSession, AuthSession?>(_MutableSession.new);
      final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>(
        (Ref ref) => ref.watch(sessionState),
      );
      final Provider<InboxRepository> inboxProvider = Provider<InboxRepository>(
        (Ref ref) => repository,
      );
      final Provider<PostponedRepository> postponedProvider =
          Provider<PostponedRepository>(
            (Ref ref) => const _PostponedRepository(),
          );
      final Provider<InboxInAppNotificationEvents> eventsProvider =
          _notificationEventsProvider();
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          AsyncNotifierProvider.autoDispose<InboxController, InboxViewState>(
            () => InboxController(
              sessionProvider,
              inboxProvider,
              postponedProvider,
              inAppNotificationEventsProvider: eventsProvider,
            ),
          );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final List<InboxInAppNotification> notifications =
          <InboxInAppNotification>[];
      final StreamSubscription<InboxInAppNotification> subscription = container
          .read(eventsProvider)
          .stream
          .listen(notifications.add);
      addTearDown(subscription.cancel);
      await container.read(provider.future);

      realtime.add(InboxPostChanged(postId: first.post.id, candidate: first));
      await _waitUntil(() => notifications.length == 1);
      await container.read(provider.notifier).refresh();
      realtime.add(InboxPostChanged(postId: first.post.id, candidate: first));
      await Future<void>.delayed(Duration.zero);
      expect(notifications, hasLength(1));

      container.read(sessionState.notifier).setSession(_session('second-user'));
      await _waitUntil(() => repository.loadCalls == 3);
      realtime.add(InboxPostChanged(postId: second.post.id, candidate: second));
      await _waitUntil(() => notifications.length == 2);

      expect(
        notifications.map((InboxInAppNotification item) => item.id),
        <String>['first', 'second'],
      );
    },
  );

  test(
    'updates an existing preview edit without a popup or new membership',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final InboxPostCandidate original = _candidate('existing');
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[ChannelPostInboxItem(candidate: original)],
          ),
        ],
        realtime: realtime.stream,
      );
      final Provider<InboxInAppNotificationEvents> eventsProvider =
          _notificationEventsProvider();
      final provider = _provider(
        repository,
        inAppNotificationEventsProvider: eventsProvider,
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final List<InboxInAppNotification> notifications =
          <InboxInAppNotification>[];
      final StreamSubscription<InboxInAppNotification> subscription = container
          .read(eventsProvider)
          .stream
          .listen(notifications.add);
      addTearDown(subscription.cancel);
      await container.read(provider.future);

      final InboxPostCandidate edited = _candidate(
        'existing',
        message: 'edited preview',
      );
      realtime.add(
        InboxPostChanged(
          postId: 'existing',
          candidate: edited,
          kind: InboxPostChangeKind.edited,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final InboxSessionViewState state = container.read(provider).requireValue;
      final ChannelPostInboxItem item =
          state.snapshot.newItems.single as ChannelPostInboxItem;
      expect(item.post.message, 'edited preview');
      expect(item.candidate.reason, original.reason);
      expect(notifications, isEmpty);

      realtime.add(
        InboxPostChanged(
          postId: 'unknown-edit',
          candidate: _candidate('unknown-edit', message: 'never shown'),
          kind: InboxPostChangeKind.edited,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(provider).requireValue.snapshot.newItems,
        hasLength(1),
      );
    },
  );

  test('thread deltas are idempotent and never create a post popup', () async {
    final StreamController<InboxRealtimeEvent> realtime =
        StreamController<InboxRealtimeEvent>();
    addTearDown(realtime.close);
    final InboxThreadCandidate first = _threadCandidate(unreadReplies: 1);
    final InboxThreadCandidate latest = _threadCandidate(unreadReplies: 3);
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[() async => InboxSnapshot()],
      realtime: realtime.stream,
    );
    final provider = _provider(repository);
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await container.read(provider.future);

    // A reply is mapped by the data layer as a hydrated thread delta. The
    // aggregate can arrive before or after it without producing a duplicate.
    realtime
      ..add(
        InboxThreadUpdated(
          sequence: 1,
          rootPostId: 'thread-root',
          candidate: first,
        ),
      )
      ..add(
        InboxThreadUpdated(
          sequence: 2,
          rootPostId: 'thread-root',
          candidate: latest,
        ),
      );
    await Future<void>.delayed(Duration.zero);

    final InboxSessionViewState state = container.read(provider).requireValue;
    expect(state.snapshot.newItems.whereType<ThreadInboxItem>(), hasLength(1));
    expect(
      (state.snapshot.newItems.single as ThreadInboxItem).thread.unreadReplies,
      3,
    );
  });

  test(
    'reactivates a postponed thread only after enabled settings and preference removal',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final ThreadInboxItem postponedItem = ThreadInboxItem(
        thread: _threadCandidate(unreadReplies: 1).thread,
        channel: _threadCandidate(unreadReplies: 1).channel,
        teamId: 'team',
        postponedAt: DateTime.utc(2026, 9, 26),
      );
      final _RecordingPostponedRepository postponed =
          _RecordingPostponedRepository();
      final _RecordingThreads threads = _RecordingThreads();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(postponedItems: <InboxItem>[postponedItem]),
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(
        repository,
        postponed: postponed,
        threads: threads,
        settings: _SettingsRepository(_enabledInboxSettings),
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      final InboxThreadCandidate candidate = _threadCandidate(
        unreadReplies: 2,
        explicitMention: true,
      );
      final InboxThreadUpdated event = InboxThreadUpdated(
        sequence: 1,
        rootPostId: 'thread-root',
        candidate: candidate,
      );
      realtime.add(event);
      await _waitUntil(() => postponed.removed.isNotEmpty);

      final InboxSnapshot reactivated = container
          .read(provider)
          .requireValue
          .snapshot;
      expect(threads.calls, <String>['isFollowing', 'follow']);
      expect(postponed.removed.single.postId, 'thread-root');
      expect(reactivated.postponedItems, isEmpty);
      expect(reactivated.newItems.single.key, 'thread:thread-root');

      // The duplicate cannot remove the same preference or follow again,
      // because the successful first operation already established New.
      realtime.add(event);
      await Future<void>.delayed(Duration.zero);
      expect(threads.calls, <String>['isFollowing', 'follow']);
      expect(postponed.removed, hasLength(1));
      expect(reactivated.newItems.single.key, 'thread:thread-root');
    },
  );

  test(
    'keeps explicit mentions postponed when settings are disabled',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final ThreadInboxItem postponedItem = ThreadInboxItem(
        thread: _threadCandidate(unreadReplies: 1).thread,
        channel: _threadCandidate(unreadReplies: 1).channel,
        teamId: 'team',
        postponedAt: DateTime.utc(2026, 9, 26),
      );
      final _RecordingPostponedRepository postponed =
          _RecordingPostponedRepository();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(postponedItems: <InboxItem>[postponedItem]),
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(
        repository,
        postponed: postponed,
        threads: _RecordingThreads(),
        settings: _SettingsRepository(_disabledInboxSettings),
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime.add(
        InboxThreadUpdated(
          sequence: 1,
          rootPostId: 'thread-root',
          candidate: _threadCandidate(unreadReplies: 2, explicitMention: true),
        ),
      );
      await _waitUntil(
        () =>
            container
                .read(provider)
                .requireValue
                .pendingThreadReactivations['thread-root'] ==
            PostponedThreadReactivationStatus.disabledBySettings,
      );

      final InboxSnapshot snapshot = container
          .read(provider)
          .requireValue
          .snapshot;
      expect(snapshot.newItems, isEmpty);
      expect(snapshot.postponedItems.single.key, 'thread:thread-root');
      expect(postponed.removed, isEmpty);
    },
  );

  test(
    'buffers an explicit mention without locally removing Postponed',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> initial = Completer<InboxSnapshot>();
      final ThreadInboxItem postponedItem = ThreadInboxItem(
        thread: _threadCandidate(unreadReplies: 1).thread,
        channel: _threadCandidate(unreadReplies: 1).channel,
        teamId: 'team',
        postponedAt: DateTime.utc(2026, 9, 26),
      );
      final _RecordingPostponedRepository postponed =
          _RecordingPostponedRepository();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[() => initial.future],
        realtime: realtime.stream,
      );
      final provider = _provider(
        repository,
        postponed: postponed,
        threads: _RecordingThreads(),
        settings: _SettingsRepository(_enabledInboxSettings),
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final Future<InboxViewState> built = container.read(provider.future);
      await _waitUntil(() => repository.loadCalls == 1);

      realtime.add(
        InboxThreadUpdated(
          sequence: 1,
          rootPostId: 'thread-root',
          candidate: _threadCandidate(unreadReplies: 2, explicitMention: true),
        ),
      );
      initial.complete(
        InboxSnapshot(postponedItems: <InboxItem>[postponedItem]),
      );
      await built;
      await _waitUntil(() => postponed.removed.isNotEmpty);

      final InboxSnapshot snapshot = container
          .read(provider)
          .requireValue
          .snapshot;
      expect(snapshot.postponedItems, isEmpty);
      expect(snapshot.newItems.single.key, 'thread:thread-root');
    },
  );

  test(
    'incomplete thread data preserves the projection before recovery',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final ThreadInboxItem existing = ThreadInboxItem(
        thread: _threadCandidate(unreadReplies: 2).thread,
        channel: _threadCandidate(unreadReplies: 2).channel,
        teamId: 'team',
      );
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[existing]),
          () async => InboxSnapshot(newItems: <InboxItem>[existing]),
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime.add(
        const InboxThreadUpdated(
          sequence: 1,
          rootPostId: 'thread-root',
          recoveryRequired: true,
        ),
      );
      await _waitUntil(() => repository.loadCalls == 2);

      expect(
        container.read(provider).requireValue.snapshot.newItems.single.key,
        'thread:thread-root',
      );
    },
  );

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
    await container.read(provider.future);

    container.read(provider.notifier).handleAppResumed();
    await _waitUntil(() => repository.loadCalls == 2);
    await Future<void>.delayed(Duration.zero);

    expect(repository.reconnectCalls, 1);
    expect(
      container.read(provider).requireValue.snapshot.newItems.single.postIds,
      <String>['missed'],
    );
  });

  test(
    'a realtime recovery request keeps old data but does not replay live deltas',
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
      await container.read(provider.future);

      realtime.add(const InboxRefreshRequired());
      await _waitUntil(
        () =>
            container.read(provider).requireValue.refreshStatus
                is OperationInProgress,
      );
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
        <String>['fresh'],
      );
      expect(repository.loadCalls, 2);
    },
  );

  test(
    'coalesces reconnect, gap, and resume into one recovery snapshot',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old')),
            ],
          ),
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('recovered')),
            ],
          ),
        ],
        realtime: realtime.stream,
      );
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime
        ..add(const InboxRefreshRequired(sequence: 4))
        ..add(const InboxRefreshRequired(sequence: 7));
      container.read(provider.notifier).handleAppResumed();
      container.read(provider.notifier).handleAppResumed();
      await _waitUntil(
        () =>
            container
                .read(provider)
                .requireValue
                .snapshot
                .newItems
                .single
                .postIds
                .single ==
            'recovered',
      );

      expect(repository.reconnectCalls, 1);
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.postIds,
        <String>['recovered'],
      );
      expect(repository.loadCalls, 2);
    },
  );

  test(
    'retries recovery with injected jitter and cancels a pending backoff',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<void> retryDelay = Completer<void>();
      final List<Duration> delays = <Duration>[];
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old')),
            ],
          ),
          () => Future<InboxSnapshot>.error(StateError('offline')),
          () async => InboxSnapshot(),
        ],
        realtime: realtime.stream,
      );
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          _provider(
            repository,
            recoveryClock: () => DateTime.utc(2026, 9, 26),
            recoveryRandom: () => 0.25,
            recoveryBackoff:
                ({
                  required int attempt,
                  required DateTime now,
                  required double random,
                }) {
                  expect(attempt, 1);
                  expect(now, DateTime.utc(2026, 9, 26));
                  expect(random, 0.25);
                  return const Duration(milliseconds: 375);
                },
            recoveryDelay: (Duration delay) {
              delays.add(delay);
              return retryDelay.future;
            },
          );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime.add(const InboxRefreshRequired());
      await _waitUntil(() => repository.loadCalls == 2 && delays.isNotEmpty);
      expect(delays, <Duration>[const Duration(milliseconds: 375)]);
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.postIds,
        <String>['old'],
      );

      container.dispose();
      retryDelay.complete();
      await Future<void>.delayed(Duration.zero);
      expect(repository.loadCalls, 2);
    },
  );

  test(
    'drops live deltas during recovery and performs one follow-up after gaps',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> firstRecovery = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old')),
            ],
          ),
          () => firstRecovery.future,
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('authoritative')),
            ],
          ),
        ],
        realtime: realtime.stream,
      );
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          _provider(repository, recoveryDelay: (_) => Future<void>.value());
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime.add(const InboxRefreshRequired(sequence: 2));
      await _waitUntil(() => repository.loadCalls == 2);
      realtime
        ..add(
          InboxPostChanged(
            postId: 'ephemeral-delta',
            candidate: _candidate('ephemeral-delta'),
            sequence: 3,
          ),
        )
        ..add(const InboxRefreshRequired(sequence: 5))
        ..add(const InboxRefreshRequired(sequence: 8));
      await Future<void>.delayed(Duration.zero);
      firstRecovery.complete(
        InboxSnapshot(
          newItems: <InboxItem>[
            ChannelPostInboxItem(candidate: _candidate('stale-recovery')),
          ],
        ),
      );
      await _waitUntil(() => repository.loadCalls == 3);
      await Future<void>.delayed(Duration.zero);

      final InboxSessionViewState state = container.read(provider).requireValue;
      expect(state.snapshot.newItems.single.postIds, <String>['authoritative']);
      expect(
        state.snapshot.newItems.expand((InboxItem item) => item.postIds),
        isNot(contains('ephemeral-delta')),
      );
      expect(repository.loadCalls, 3);
    },
  );

  test(
    'replays initial realtime deltas atomically in transport sequence',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> initial = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[() => initial.future],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final Future<InboxViewState> built = container.read(provider.future);
      await _waitUntil(() => repository.loadCalls == 1);

      final InboxPostCandidate late = _candidate('late');
      // Delivery is intentionally out of order: sequence 1 must remove before
      // sequence 2 inserts, leaving the post in the initial projection.
      realtime.add(
        InboxPostChanged(postId: late.post.id, candidate: late, sequence: 2),
      );
      realtime.add(
        InboxPostChanged(postId: late.post.id, candidate: null, sequence: 1),
      );
      await Future<void>.delayed(Duration.zero);

      initial.complete(InboxSnapshot());
      final InboxViewState state = await built;
      expect(state.snapshot.newItems.single.postIds, <String>['late']);
    },
  );

  test(
    'bounded initial realtime buffer requests one recovery snapshot',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> initial = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () => initial.future,
          () => Future<InboxSnapshot>.value(InboxSnapshot()),
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final Future<InboxViewState> built = container.read(provider.future);
      await _waitUntil(() => repository.loadCalls == 1);

      for (var index = 0; index < 129; index++) {
        realtime.add(
          InboxPostChanged(
            postId: 'post-$index',
            candidate: null,
            sequence: index + 1,
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      initial.complete(InboxSnapshot());
      await built;
      await _waitUntil(() => repository.loadCalls == 2);
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
      final InboxViewState initial = await container.read(provider.future);
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
    'a manual refresh replays buffered deltas without replaying a foreground notification',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> refresh = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old')),
            ],
          ),
          () => refresh.future,
        ],
        realtime: realtime.stream,
      );
      final Provider<InboxInAppNotificationEvents> eventsProvider =
          _notificationEventsProvider();
      final provider = _provider(
        repository,
        inAppNotificationEventsProvider: eventsProvider,
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      final List<InboxInAppNotification> notifications =
          <InboxInAppNotification>[];
      final StreamSubscription<InboxInAppNotification> subscription = container
          .read(eventsProvider)
          .stream
          .listen(notifications.add);
      addTearDown(subscription.cancel);
      await container.read(provider.future);

      final Future<void> request = container.read(provider.notifier).refresh();
      await _waitUntil(
        () =>
            container.read(provider).requireValue.refreshStatus
                is OperationInProgress,
      );
      final InboxPostCandidate duringRefresh = _candidate('during-refresh');
      realtime.add(
        InboxPostChanged(
          postId: duringRefresh.post.id,
          candidate: duringRefresh,
        ),
      );
      refresh.complete(
        InboxSnapshot(
          newItems: <InboxItem>[
            ChannelPostInboxItem(candidate: _candidate('fresh')),
          ],
        ),
      );
      await request;

      expect(
        container
            .read(provider)
            .requireValue
            .snapshot
            .newItems
            .expand((InboxItem item) => item.postIds),
        unorderedEquals(<String>['fresh', 'during-refresh']),
      );
      expect(notifications, isEmpty);
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
      await container.read(provider.future);

      expect(await container.read(provider.notifier).markRead(bundle), isTrue);

      expect(repository.markedRead, same(bundle));
      expect(container.read(provider).value?.snapshot.newItems, isEmpty);
    },
  );

  test(
    'an action completing after an account switch cannot overwrite the new session snapshot',
    () async {
      final _AccountSwitchRepository repository = _AccountSwitchRepository();
      final NotifierProvider<_MutableSession, AuthSession?> sessionState =
          NotifierProvider<_MutableSession, AuthSession?>(_MutableSession.new);
      final Provider<AuthSession?> sessionProvider = Provider<AuthSession?>(
        (Ref ref) => ref.watch(sessionState),
      );
      final Provider<InboxRepository> inboxProvider = Provider<InboxRepository>(
        (Ref ref) => repository,
      );
      final Provider<PostponedRepository> postponedProvider =
          Provider<PostponedRepository>(
            (Ref ref) => const _PostponedRepository(),
          );
      final AsyncNotifierProvider<InboxController, InboxViewState> provider =
          AsyncNotifierProvider.autoDispose<InboxController, InboxViewState>(
            () => InboxController(
              sessionProvider,
              inboxProvider,
              postponedProvider,
            ),
          );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      final InboxItem firstItem = container
          .read(provider)
          .requireValue
          .snapshot
          .newItems
          .single;
      final Future<bool> action = container
          .read(provider.notifier)
          .markRead(firstItem);
      await repository.firstMarkReadStarted.future;

      container.read(sessionState.notifier).setSession(_session('second-user'));
      await _waitUntil(() => repository.loadCalls == 2);
      expect(
        container.read(provider).requireValue.snapshot.newItems.single.postIds,
        <String>['second-user-item'],
      );

      repository.completeFirstMarkRead();
      await action;
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(provider).requireValue.snapshot.newItems.single.postIds,
        <String>['second-user-item'],
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
    await container.read(provider.future);
    expect(await container.read(provider.notifier).postpone(bundle), isTrue);

    final InboxSnapshot snapshot = container.read(provider).value!.snapshot;
    expect(snapshot.newItems.single.postIds, <String>['first']);
    expect(snapshot.postponedItems.single.postIds, <String>['second']);
    expect(postponed.saved.single.postId, 'second');
  });

  test(
    'partial Postponed save reconciles authoritative state before moving New',
    () async {
      final ChannelPostInboxItem item = ChannelPostInboxItem(
        candidate: _candidate('new'),
      );
      final PostponedReference reference = PostponedReference(
        postId: 'new',
        kind: PostponedReferenceKind.post,
        addedAt: DateTime.utc(2026, 9, 27),
      );
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[item]),
        ],
        postponedResults: <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            postponedItems: <InboxItem>[
              UnavailablePostponedInboxItem(reference: reference),
            ],
          ),
        ],
      );
      final provider = _provider(
        repository,
        postponed: _PartialPostponedRepository(
          saveOutcome: PostponedBatchOutcome(
            requested: <PostponedReference>[reference],
            confirmed: const <PostponedReference>[],
            requiresReconciliation: true,
          ),
        ),
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      expect(await container.read(provider.notifier).postpone(item), isFalse);

      final InboxSnapshot snapshot = container
          .read(provider)
          .requireValue
          .snapshot;
      expect(repository.postponedReloadCalls, 1);
      expect(snapshot.newItems, isEmpty);
      expect(
        snapshot.postponedItems.single,
        isA<UnavailablePostponedInboxItem>(),
      );
      expect(
        (snapshot.postponedItems.single as UnavailablePostponedInboxItem)
            .reference,
        same(reference),
      );
    },
  );

  test(
    'partial placeholder removal keeps it visible when reconciliation retains it',
    () async {
      final PostponedReference reference = PostponedReference(
        postId: 'missing',
        kind: PostponedReferenceKind.thread,
        targetPostId: 'target',
        addedAt: DateTime.utc(2026, 9, 27),
      );
      final UnavailablePostponedInboxItem item = UnavailablePostponedInboxItem(
        reference: reference,
      );
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(postponedItems: <InboxItem>[item]),
        ],
        postponedResults: <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(postponedItems: <InboxItem>[item]),
        ],
      );
      final provider = _provider(
        repository,
        postponed: _PartialPostponedRepository(
          removeOutcome: PostponedBatchOutcome(
            requested: <PostponedReference>[reference],
            confirmed: const <PostponedReference>[],
            requiresReconciliation: true,
          ),
        ),
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      expect(await container.read(provider.notifier).remove(item), isFalse);

      final UnavailablePostponedInboxItem retained =
          container.read(provider).requireValue.snapshot.postponedItems.single
              as UnavailablePostponedInboxItem;
      expect(repository.postponedReloadCalls, 1);
      expect(retained.reference.kind, PostponedReferenceKind.thread);
      expect(retained.reference.targetPostId, 'target');
      expect(retained.reference.addedAt, reference.addedAt);
    },
  );

  test(
    'postponing a thread saves, marks read, and unfollows before moving it',
    () async {
      final ThreadInboxItem item = ThreadInboxItem(
        thread: _threadCandidate(unreadReplies: 2).thread,
        channel: _threadCandidate(unreadReplies: 2).channel,
        teamId: 'team',
      );
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[item]),
        ],
      );
      final _RecordingPostponedRepository postponed =
          _RecordingPostponedRepository();
      final _RecordingThreads threads = _RecordingThreads();
      final provider = _provider(
        repository,
        postponed: postponed,
        threads: threads,
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      expect(await container.read(provider.notifier).postpone(item), isTrue);

      final InboxSessionViewState state = container.read(provider).requireValue;
      expect(state.snapshot.newItems, isEmpty);
      expect(state.snapshot.postponedItems.single.key, 'thread:thread-root');
      expect(postponed.saved.single.kind, PostponedReferenceKind.thread);
      expect(postponed.saved.single.targetPostId, 'thread-root');
      expect(threads.calls, <String>['markRead', 'unfollow']);
      expect(state.pendingThreadPostponeSideEffects, isEmpty);
    },
  );

  test('a failed thread preference save keeps the item in New', () async {
    final ThreadInboxItem item = ThreadInboxItem(
      thread: _threadCandidate(unreadReplies: 1).thread,
      channel: _threadCandidate(unreadReplies: 1).channel,
      teamId: 'team',
    );
    final _InboxRepository repository = _InboxRepository(
      <Future<InboxSnapshot> Function()>[
        () async => InboxSnapshot(newItems: <InboxItem>[item]),
      ],
    );
    final _RecordingPostponedRepository postponed =
        _RecordingPostponedRepository(saveFailures: 1);
    final _RecordingThreads threads = _RecordingThreads();
    final provider = _provider(
      repository,
      postponed: postponed,
      threads: threads,
    );
    final ProviderContainer container = ProviderContainer()
      ..listen(provider, (_, _) {});
    addTearDown(container.dispose);
    await container.read(provider.future);

    expect(await container.read(provider.notifier).postpone(item), isFalse);

    final InboxSessionViewState state = container.read(provider).requireValue;
    expect(state.snapshot.newItems.single.key, 'thread:thread-root');
    expect(state.snapshot.postponedItems, isEmpty);
    expect(threads.calls, isEmpty);
  });

  test(
    'a failed thread side effect is observable and retries without resaving',
    () async {
      final ThreadInboxItem item = ThreadInboxItem(
        thread: _threadCandidate(unreadReplies: 1).thread,
        channel: _threadCandidate(unreadReplies: 1).channel,
        teamId: 'team',
      );
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(newItems: <InboxItem>[item]),
        ],
      );
      final _RecordingPostponedRepository postponed =
          _RecordingPostponedRepository();
      final _RecordingThreads threads = _RecordingThreads(unfollowFailures: 1);
      final provider = _provider(
        repository,
        postponed: postponed,
        threads: threads,
      );
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      expect(await container.read(provider.notifier).postpone(item), isTrue);
      expect(
        container
            .read(provider)
            .requireValue
            .pendingThreadPostponeSideEffects['thread-root']
            ?.pending,
        <PostponeThreadSideEffect>{PostponeThreadSideEffect.unfollow},
      );
      expect(postponed.saved, hasLength(1));

      expect(
        await container
            .read(provider.notifier)
            .retryPostponedThreadSideEffects('thread-root'),
        isTrue,
      );
      expect(postponed.saved, hasLength(1));
      expect(threads.calls, <String>['markRead', 'unfollow', 'unfollow']);
      expect(
        container.read(provider).requireValue.pendingThreadPostponeSideEffects,
        isEmpty,
      );
      expect(
        await container
            .read(provider.notifier)
            .retryPostponedThreadSideEffects('thread-root'),
        isFalse,
      );
      expect(postponed.saved, hasLength(1));
      expect(threads.calls, <String>['markRead', 'unfollow', 'unfollow']);
    },
  );

  test(
    'reconciles only Postponed for a cross-device preference change',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('new')),
            ],
            postponedItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old-postponed')),
            ],
          ),
        ],
        postponedResults: <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('new')),
            ],
            postponedItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('fresh-postponed')),
            ],
          ),
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime.add(
        const InboxRefreshRequired(scope: InboxRefreshScope.postponed),
      );
      await _waitUntil(() => repository.postponedReloadCalls == 1);

      final InboxSnapshot snapshot = container
          .read(provider)
          .requireValue
          .snapshot;
      expect(repository.loadCalls, 1);
      expect(snapshot.newItems.single.postIds, <String>['new']);
      expect(snapshot.postponedItems.single.postIds, <String>[
        'fresh-postponed',
      ]);
    },
  );

  test(
    'retains the useful snapshot when scoped Postponed reconciliation fails',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(
            newItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('new')),
            ],
            postponedItems: <InboxItem>[
              ChannelPostInboxItem(candidate: _candidate('old-postponed')),
            ],
          ),
        ],
        postponedResults: <Future<InboxSnapshot> Function()>[
          () => Future<InboxSnapshot>(() => throw StateError('offline')),
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime.add(
        const InboxRefreshRequired(scope: InboxRefreshScope.postponed),
      );
      await _waitUntil(
        () =>
            container.read(provider).requireValue.refreshStatus
                is OperationFailed,
      );

      final InboxSnapshot snapshot = container
          .read(provider)
          .requireValue
          .snapshot;
      expect(snapshot.newItems.single.postIds, <String>['new']);
      expect(snapshot.postponedItems.single.postIds, <String>['old-postponed']);
      expect(repository.loadCalls, 1);
    },
  );

  test(
    'coalesces concurrent eligibility context events into one recovery',
    () async {
      final StreamController<InboxRealtimeEvent> realtime =
          StreamController<InboxRealtimeEvent>();
      addTearDown(realtime.close);
      final Completer<InboxSnapshot> recovery = Completer<InboxSnapshot>();
      final _InboxRepository repository = _InboxRepository(
        <Future<InboxSnapshot> Function()>[
          () async => InboxSnapshot(),
          () => recovery.future,
        ],
        realtime: realtime.stream,
      );
      final provider = _provider(repository);
      final ProviderContainer container = ProviderContainer()
        ..listen(provider, (_, _) {});
      addTearDown(container.dispose);
      await container.read(provider.future);

      realtime
        ..add(
          const InboxEligibilityContextChanged(
            sequence: 1,
            kind: InboxEligibilityContextChangeKind.desktopNotifications,
          ),
        )
        ..add(
          const InboxEligibilityContextChanged(
            sequence: 2,
            kind: InboxEligibilityContextChangeKind.channelMembership,
          ),
        );
      await _waitUntil(() => repository.loadCalls == 2);
      await Future<void>.delayed(Duration.zero);
      recovery.complete(InboxSnapshot());
      await Future<void>.delayed(Duration.zero);

      expect(repository.loadCalls, 2);
    },
  );
}

InboxPostCandidate _candidate(String id, {String? message}) =>
    InboxPostCandidate(
      post: Post(
        id: id,
        channelId: 'channel',
        author: const PostAuthor(id: 'other', displayName: 'Other'),
        sentAt: DateTime.utc(2026),
        message: message ?? id,
      ),
      channel: const SidebarChannel(
        id: 'channel',
        teamId: 'team',
        name: 'channel',
        displayName: 'Channel',
        kind: ChannelKind.directMessage,
      ),
      reason: InboxAttentionReason.allMessagesSubscription,
    );

const InboxSettings _enabledInboxSettings = InboxSettings();
const InboxSettings _disabledInboxSettings = InboxSettings(
  postponed: InboxPostponedSettings(reactivateOnMention: false),
);

AuthSession _session(String userId) => AuthSession(
  serverUrl: Uri(scheme: 'https', host: 'chat.example.test'),
  userId: userId,
  username: userId,
);

final class _MutableSession extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => _session('first-user');

  void setSession(AuthSession session) => state = session;
}

InboxThreadCandidate _threadCandidate({
  required int unreadReplies,
  bool explicitMention = false,
}) => InboxThreadCandidate(
  thread: FollowedThread(
    root: Post(
      id: 'thread-root',
      channelId: 'channel',
      author: const PostAuthor(id: 'other', displayName: 'Other'),
      sentAt: DateTime.utc(2026),
      message: 'Root',
    ),
    replyCount: unreadReplies,
    lastReplyAt: DateTime.utc(2026, 1, 1, 0, unreadReplies),
    lastViewedAt: DateTime.utc(2025),
    unreadReplies: unreadReplies,
    unreadMentions: 0,
  ),
  channel: const SidebarChannel(
    id: 'channel',
    teamId: 'team',
    name: 'channel',
    displayName: 'Channel',
    kind: ChannelKind.publicChannel,
  ),
  teamId: 'team',
  hasNewExplicitMention: explicitMention,
);

AsyncNotifierProvider<InboxController, InboxViewState> _provider(
  InboxRepository repository, {
  PostponedRepository postponed = const _PostponedRepository(),
  ThreadRepository? threads,
  InboxSettingsRepository? settings,
  DateTime Function()? recoveryClock,
  double Function()? recoveryRandom,
  InboxRecoveryBackoff? recoveryBackoff,
  InboxRecoveryDelay? recoveryDelay,
  Provider<InboxInAppNotificationEvents>? inAppNotificationEventsProvider,
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
  final Provider<ThreadRepository>? threadProvider = threads == null
      ? null
      : Provider<ThreadRepository>((Ref ref) => threads);
  final Provider<InboxSettingsRepository>? settingsProvider = settings == null
      ? null
      : Provider<InboxSettingsRepository>((Ref ref) => settings);
  return AsyncNotifierProvider.autoDispose<InboxController, InboxViewState>(
    () => InboxController(
      sessionProvider,
      inboxProvider,
      postponedProvider,
      threadProvider: threadProvider,
      settingsProvider: settingsProvider,
      inAppNotificationEventsProvider: inAppNotificationEventsProvider,
      recoveryClock: recoveryClock,
      recoveryRandom: recoveryRandom,
      recoveryBackoff: recoveryBackoff,
      recoveryDelay: recoveryDelay,
    ),
  );
}

Provider<InboxInAppNotificationEvents> _notificationEventsProvider() =>
    Provider<InboxInAppNotificationEvents>(
      (Ref ref) => InboxInAppNotificationEvents(),
    );

final class _InboxRepository extends InboxRepository {
  _InboxRepository(
    this.results, {
    this.postponedResults = const <Future<InboxSnapshot> Function()>[],
    this.realtime = const Stream<InboxRealtimeEvent>.empty(),
  });
  final List<Future<InboxSnapshot> Function()> results;
  final List<Future<InboxSnapshot> Function()> postponedResults;
  final Stream<InboxRealtimeEvent> realtime;
  var _index = 0;
  var loadCalls = 0;
  var postponedReloadCalls = 0;
  var reconnectCalls = 0;
  InboxItem? markedRead;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) {
    loadCalls++;
    return results[_index++]();
  }

  @override
  Future<InboxSnapshot> reloadPostponed({
    required AuthSession session,
    required InboxSnapshot current,
  }) {
    postponedReloadCalls++;
    return postponedResults[postponedReloadCalls - 1]();
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
}

final class _AccountSwitchRepository extends InboxRepository {
  final Completer<void> firstMarkReadStarted = Completer<void>();
  final Completer<void> _firstMarkRead = Completer<void>();
  var loadCalls = 0;

  @override
  Future<InboxSnapshot> load({required AuthSession session}) async {
    loadCalls++;
    return InboxSnapshot(
      newItems: <InboxItem>[
        ChannelPostInboxItem(candidate: _candidate('${session.userId}-item')),
      ],
    );
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required InboxItem item,
  }) {
    if (!firstMarkReadStarted.isCompleted) firstMarkReadStarted.complete();
    return _firstMarkRead.future;
  }

  void completeFirstMarkRead() => _firstMarkRead.complete();
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
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

final class _SettingsRepository extends InboxSettingsRepository {
  const _SettingsRepository(this.settings);

  final InboxSettings settings;

  @override
  Future<InboxSettingsSnapshot> load({required AuthSession session}) async =>
      InboxSettingsSnapshot(
        settings: settings,
        state: InboxSettingsLoadState.parsed,
      );

  @override
  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
  }) async {}
}

final class _RecordingPostponedRepository extends PostponedRepository {
  _RecordingPostponedRepository({this.saveFailures = 0});

  List<PostponedReference> saved = <PostponedReference>[];
  List<PostponedReference> removed = <PostponedReference>[];
  int saveFailures;

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    removed = List<PostponedReference>.of(references);
  }

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    if (saveFailures-- > 0) throw StateError('save failed');
    saved = List<PostponedReference>.of(references);
  }
}

final class _PartialPostponedRepository extends PostponedRepository {
  _PartialPostponedRepository({this.saveOutcome, this.removeOutcome});

  final PostponedBatchOutcome? saveOutcome;
  final PostponedBatchOutcome? removeOutcome;

  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(const <PostponedReference>[]);

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}

  @override
  Future<PostponedBatchOutcome> saveWithOutcome({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async => saveOutcome ?? PostponedBatchOutcome.confirmed(references);

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}

  @override
  Future<PostponedBatchOutcome> removeWithOutcome({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async => removeOutcome ?? PostponedBatchOutcome.confirmed(references);
}

final class _RecordingThreads extends ThreadRepository {
  _RecordingThreads({this.unfollowFailures = 0});

  int unfollowFailures;
  bool following = false;
  final List<String> calls = <String>[];

  @override
  Future<bool> isFollowing({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async {
    calls.add('isFollowing');
    return following;
  }

  @override
  Future<void> follow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async {
    calls.add('follow');
    following = true;
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) async {
    calls.add('markRead');
  }

  @override
  Future<void> unfollow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async {
    calls.add('unfollow');
    if (unfollowFailures-- > 0) throw StateError('unfollow failed');
  }
}
