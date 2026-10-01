import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_post_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// One foreground-only notification produced by a newly received Inbox post.
final class InboxInAppNotification {
  const InboxInAppNotification({required this.candidate});

  final InboxPostCandidate candidate;

  String get id => candidate.post.id;
}

final class InboxViewState {
  const InboxViewState({
    required this.snapshot,
    this.refreshStatus = const OperationStatus.idle(),
    this.connectionStatus = InboxConnectionStatus.disconnected,
    this.inAppNotification,
  });

  final InboxSnapshot snapshot;
  final OperationStatus refreshStatus;
  final InboxConnectionStatus connectionStatus;
  final InboxInAppNotification? inAppNotification;

  InboxViewState copyWith({
    InboxSnapshot? snapshot,
    OperationStatus? refreshStatus,
    InboxConnectionStatus? connectionStatus,
    InboxInAppNotification? inAppNotification,
  }) => InboxViewState(
    snapshot: snapshot ?? this.snapshot,
    refreshStatus: refreshStatus ?? this.refreshStatus,
    connectionStatus: connectionStatus ?? this.connectionStatus,
    inAppNotification: inAppNotification ?? this.inAppNotification,
  );
}

final class InboxController extends AsyncNotifier<InboxViewState> {
  InboxController(
    this._sessionProvider,
    this._inboxProvider,
    this._postponedProvider,
  );

  final Provider<AuthSession?> _sessionProvider;
  final Provider<InboxRepository> _inboxProvider;
  final Provider<PostponedRepository> _postponedProvider;
  RequestCancellation? _cancellation;
  AuthSession? _session;
  InboxRepository? _inbox;
  PostponedRepository? _postponed;
  StreamSubscription<InboxRealtimeEvent>? _realtimeSubscription;
  final List<InboxPostChanged> _pendingRealtimePostChanges =
      <InboxPostChanged>[];
  final Set<String> _individuallyViewedPostIds = <String>{};
  _InboxOperation _operation = _InboxOperation.idle;
  bool _realtimeRefreshQueued = false;
  var _buildGeneration = 0;

  @override
  Future<InboxViewState> build() async {
    final int generation = ++_buildGeneration;
    _cancellation?.cancel();
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    _pendingRealtimePostChanges.clear();
    _individuallyViewedPostIds.clear();
    _operation = _InboxOperation.idle;
    _realtimeRefreshQueued = false;
    ref.onDispose(() {
      cancellation.cancel();
      if (generation == _buildGeneration) {
        _buildGeneration += 1;
        unawaited(_realtimeSubscription?.cancel());
      }
    });
    final AuthSession? session = ref.watch(_sessionProvider);
    _session = session;
    if (session == null) {
      _inbox = null;
      _postponed = null;
      return InboxViewState(snapshot: InboxSnapshot());
    }
    final InboxRepository inbox = ref.watch(_inboxProvider);
    final PostponedRepository postponed = ref.watch(_postponedProvider);
    _inbox = inbox;
    _postponed = postponed;
    final InboxViewState result = InboxViewState(
      snapshot: await cancellation.run(() => inbox.load(session: session)),
    );
    unawaited(
      _listenRealtimeAfterBuild(
        session: session,
        inbox: inbox,
        generation: generation,
      ),
    );
    return result;
  }

  Future<void> _listenRealtimeAfterBuild({
    required AuthSession session,
    required InboxRepository inbox,
    required int generation,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (_cancellation?.isCancelled != false || generation != _buildGeneration) {
      return;
    }
    _listenRealtime(session: session, inbox: inbox, generation: generation);
  }

  void _listenRealtime({
    required AuthSession session,
    required InboxRepository inbox,
    required int generation,
  }) {
    _realtimeSubscription = inbox
        .watch(session: session)
        .listen(
          (InboxRealtimeEvent event) {
            if (generation == _buildGeneration) _onRealtimeEvent(event);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation == _buildGeneration) {
              _setConnectionStatus(InboxConnectionStatus.disconnected);
            }
          },
          onDone: () {
            if (generation == _buildGeneration) {
              _setConnectionStatus(InboxConnectionStatus.disconnected);
            }
          },
        );
  }

  /// Replaces a potentially half-open socket and reconciles events missed
  /// while the process was suspended.
  void handleAppResumed() {
    final InboxRepository? inbox = _inbox;
    if (_session == null || inbox == null) return;
    _setConnectionStatus(InboxConnectionStatus.connecting);
    inbox.reconnectRealtime();
    _realtimeRefreshQueued = true;
    unawaited(_refreshFromRealtime());
  }

  void _onRealtimeEvent(InboxRealtimeEvent event) {
    final InboxViewState? current = state.value;
    if (current == null) return;
    switch (event) {
      case InboxConnectionChanged(:final status):
        _setConnectionStatus(status);
      case InboxPostChanged():
        if (_operation != _InboxOperation.idle) {
          _pendingRealtimePostChanges.add(event);
          return;
        }
        _applyRealtimePostChange(current, event);
      case InboxRefreshRequired():
        _realtimeRefreshQueued = true;
        unawaited(_refreshFromRealtime());
    }
  }

  void _applyRealtimePostChange(
    InboxViewState current,
    InboxPostChanged change,
  ) {
    final InboxPostCandidate? effectiveCandidate =
        _individuallyViewedPostIds.contains(change.postId)
        ? null
        : change.candidate;
    final bool wasAlreadyPresent = current.snapshot.newItems.any(
      (InboxItem item) => item.postIds.contains(change.postId),
    );
    final InboxSnapshot snapshot = applyInboxPostChange(
      snapshot: current.snapshot,
      postId: change.postId,
      candidate: effectiveCandidate,
    );
    final bool wasAdded =
        !wasAlreadyPresent &&
        effectiveCandidate != null &&
        snapshot.newItems.any(
          (InboxItem item) => item.postIds.contains(change.postId),
        );
    state = AsyncData(
      current.copyWith(
        snapshot: snapshot,
        inAppNotification: wasAdded
            ? InboxInAppNotification(candidate: effectiveCandidate)
            : current.inAppNotification,
      ),
    );
  }

  void _setConnectionStatus(InboxConnectionStatus status) {
    final InboxViewState? current = state.value;
    if (current == null || current.connectionStatus == status) return;
    state = AsyncData(current.copyWith(connectionStatus: status));
  }

  Future<void> _refreshFromRealtime() async {
    if (_operation != _InboxOperation.idle || !_realtimeRefreshQueued) return;
    _realtimeRefreshQueued = false;
    await refresh();
  }

  Future<void> refresh() async {
    final InboxViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        inbox == null) {
      return;
    }
    _operation = _InboxOperation.refresh;
    state = AsyncData(
      current.copyWith(refreshStatus: const OperationStatus.inProgress()),
    );
    try {
      final RequestCancellation? cancellation = _cancellation;
      if (cancellation == null) return;
      final InboxSnapshot snapshot = await cancellation.run(
        () => inbox.load(session: session),
      );
      final InboxViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: snapshot,
          refreshStatus: const OperationStatus.idle(),
        ),
      );
    } on Object catch (error) {
      if (_cancellation?.isCancelled == false) {
        final InboxViewState latest = state.value ?? current;
        state = AsyncData(
          latest.copyWith(refreshStatus: OperationStatus.failed(error)),
        );
      }
    } finally {
      _finishBusyOperation();
    }
  }

  Future<bool> postpone(InboxItem item) =>
      _move(_latestDirectMessage(item), toPostponed: true);
  Future<bool> remove(InboxItem item) => _move(item, toPostponed: false);

  InboxItem _latestDirectMessage(InboxItem item) => switch (item) {
    DirectMessageBundleInboxItem(messages: final messages) =>
      DirectMessageBundleInboxItem(
        channelId: item.channelId,
        authorId: item.authorId,
        automationClass: item.automationClass,
        messages: <InboxPostCandidate>[messages.last],
      ),
    _ => item,
  };

  /// Removes an unfollowed CRT thread from both volatile Inbox queues.
  void removeUnfollowedThread(String rootPostId) {
    final InboxViewState? current = state.value;
    if (current == null) return;
    List<InboxItem> withoutThread(Iterable<InboxItem> items) => items
        .where(
          (InboxItem item) =>
              item is! ThreadInboxItem || item.thread.id != rootPostId,
        )
        .toList(growable: false);
    state = AsyncData(
      current.copyWith(
        snapshot: InboxSnapshot(
          newItems: withoutThread(current.snapshot.newItems),
          postponedItems: withoutThread(current.snapshot.postponedItems),
          builtAt: current.snapshot.builtAt,
          hasIncompleteMentionReconstruction:
              current.snapshot.hasIncompleteMentionReconstruction,
        ),
      ),
    );
  }

  Future<bool> markRead(InboxItem item) async {
    final InboxViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        inbox == null) {
      return false;
    }
    _operation = _InboxOperation.markRead;
    try {
      final bool individuallyViewed =
          item is ChannelPostInboxItem &&
          !item.candidate.channel.isDialog &&
          _channelRootCount(current.snapshot.newItems, item.post.channelId) > 1;
      if (individuallyViewed) {
        await inbox.markPostViewed(session: session, item: item);
        _individuallyViewedPostIds.add(item.post.id);
      } else {
        await inbox.markRead(session: session, item: item);
      }
      final List<InboxItem> newItems = current.snapshot.newItems
          .where(
            (InboxItem candidate) => !_isReadBy(
              candidate,
              item,
              individuallyViewed: individuallyViewed,
            ),
          )
          .toList(growable: false);
      final InboxViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: InboxSnapshot(
            newItems: newItems,
            postponedItems: current.snapshot.postponedItems,
            builtAt: current.snapshot.builtAt,
            hasIncompleteMentionReconstruction:
                current.snapshot.hasIncompleteMentionReconstruction,
          ),
          refreshStatus: const OperationStatus.idle(),
        ),
      );
      return true;
    } on Object {
      return false;
    } finally {
      _finishBusyOperation();
    }
  }

  int _channelRootCount(Iterable<InboxItem> items, String channelId) => items
      .whereType<ChannelPostInboxItem>()
      .where((ChannelPostInboxItem item) => item.post.channelId == channelId)
      .length;

  bool _isReadBy(
    InboxItem candidate,
    InboxItem readItem, {
    required bool individuallyViewed,
  }) {
    if (individuallyViewed) return candidate.key == readItem.key;
    if (readItem is ThreadInboxItem) return candidate.key == readItem.key;
    final String channelId = switch (readItem) {
      ChannelPostInboxItem(:final post) => post.channelId,
      DirectMessageBundleInboxItem(:final channelId) => channelId,
      ThreadInboxItem() => '',
    };
    return switch (candidate) {
      ChannelPostInboxItem(:final post) => post.channelId == channelId,
      DirectMessageBundleInboxItem(channelId: final candidateChannelId) =>
        candidateChannelId == channelId,
      ThreadInboxItem() => false,
    };
  }

  Future<bool> _move(InboxItem item, {required bool toPostponed}) async {
    final InboxViewState? current = state.value;
    final AuthSession? session = _session;
    final PostponedRepository? postponed = _postponed;
    if (_operation != _InboxOperation.idle ||
        current == null ||
        session == null ||
        postponed == null) {
      return false;
    }
    _operation = _InboxOperation.move;
    final DateTime now = DateTime.now().toUtc();
    final PostponedReferenceKind kind = item is ThreadInboxItem
        ? PostponedReferenceKind.thread
        : PostponedReferenceKind.post;
    final List<PostponedReference> references = item.postIds
        .map(
          (String id) =>
              PostponedReference(postId: id, kind: kind, addedAt: now),
        )
        .toList(growable: false);
    try {
      if (toPostponed) {
        await postponed.save(session: session, references: references);
        // TODO(inbox): postponing a CRT thread must also mark it read and
        // unfollow it with retry/backoff after the preference is durable.
      } else {
        await postponed.remove(session: session, references: references);
      }
      final List<InboxItem> newItems = List<InboxItem>.of(
        current.snapshot.newItems,
      );
      final List<InboxItem> postponedItems = List<InboxItem>.of(
        current.snapshot.postponedItems,
      );
      if (toPostponed) {
        _removePostIds(newItems, item);
        postponedItems.add(_withPostponedAt(item, now));
      } else {
        _removePostIds(postponedItems, item);
      }
      final InboxViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: InboxSnapshot(
            newItems: newItems,
            postponedItems: postponedItems,
            builtAt: current.snapshot.builtAt,
            hasIncompleteMentionReconstruction:
                current.snapshot.hasIncompleteMentionReconstruction,
          ),
          refreshStatus: const OperationStatus.idle(),
        ),
      );
      return true;
    } on Object {
      return false;
    } finally {
      _finishBusyOperation();
    }
  }

  void _finishBusyOperation() {
    _operation = _InboxOperation.idle;
    final InboxViewState? current = state.value;
    if (current != null && _pendingRealtimePostChanges.isNotEmpty) {
      for (final InboxPostChanged change in _pendingRealtimePostChanges) {
        final InboxViewState? latest = state.value;
        if (latest != null) _applyRealtimePostChange(latest, change);
      }
      _pendingRealtimePostChanges.clear();
    }
    if (_realtimeRefreshQueued) unawaited(_refreshFromRealtime());
  }

  void _removePostIds(List<InboxItem> items, InboxItem removed) {
    final Set<String> removedIds = removed.postIds.toSet();
    for (var index = items.length - 1; index >= 0; index--) {
      final InboxItem current = items[index];
      if (current is DirectMessageBundleInboxItem) {
        final Set<String> retainedIds = current.postIds.toSet()
          ..removeAll(removedIds);
        if (retainedIds.length == current.postIds.length) continue;
        if (retainedIds.isEmpty) {
          items.removeAt(index);
        } else {
          items[index] = current.retainingPostIds(retainedIds);
        }
      } else if (current.postIds.any(removedIds.contains)) {
        items.removeAt(index);
      }
    }
  }

  InboxItem _withPostponedAt(InboxItem item, DateTime at) => switch (item) {
    ThreadInboxItem() => ThreadInboxItem(
      thread: item.thread,
      channel: item.channel,
      teamId: item.teamId,
      rootAttentionReason: item.rootAttentionReason,
      reactivatesPostponed: item.reactivatesPostponed,
      postponedAt: at,
    ),
    ChannelPostInboxItem() => ChannelPostInboxItem(
      candidate: item.candidate,
      postponedAt: at,
    ),
    DirectMessageBundleInboxItem() => DirectMessageBundleInboxItem(
      channelId: item.channelId,
      authorId: item.authorId,
      automationClass: item.automationClass,
      messages: item.messages,
      postponedAt: at,
    ),
  };
}

enum _InboxOperation { idle, refresh, markRead, move }
