import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_post_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

final class InboxViewState {
  const InboxViewState({
    required this.snapshot,
    this.isRefreshing = false,
    this.refreshFailed = false,
    this.connectionStatus = InboxConnectionStatus.disconnected,
  });

  final InboxSnapshot snapshot;
  final bool isRefreshing;
  final bool refreshFailed;
  final InboxConnectionStatus connectionStatus;

  InboxViewState copyWith({
    InboxSnapshot? snapshot,
    bool? isRefreshing,
    bool? refreshFailed,
    InboxConnectionStatus? connectionStatus,
  }) => InboxViewState(
    snapshot: snapshot ?? this.snapshot,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
    connectionStatus: connectionStatus ?? this.connectionStatus,
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
  late final RequestCancellation _cancellation;
  AuthSession? _session;
  InboxRepository? _inbox;
  PostponedRepository? _postponed;
  StreamSubscription<InboxRealtimeEvent>? _realtimeSubscription;
  final List<InboxPostChanged> _pendingRealtimePostChanges =
      <InboxPostChanged>[];
  bool _busy = false;
  bool _realtimeRefreshQueued = false;

  @override
  Future<InboxViewState> build() async {
    _cancellation = RequestCancellation();
    ref.onDispose(() {
      _cancellation.cancel();
      unawaited(_realtimeSubscription?.cancel());
    });
    _session = ref.watch(_sessionProvider);
    if (_session == null) {
      return InboxViewState(snapshot: InboxSnapshot());
    }
    _inbox = ref.watch(_inboxProvider);
    _postponed = ref.watch(_postponedProvider);
    final InboxViewState result = InboxViewState(
      snapshot: await _cancellation.run(() => _inbox!.load(session: _session!)),
    );
    unawaited(_listenRealtimeAfterBuild(session: _session!, inbox: _inbox!));
    return result;
  }

  Future<void> _listenRealtimeAfterBuild({
    required AuthSession session,
    required InboxRepository inbox,
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (_cancellation.isCancelled) return;
    _listenRealtime(session: session, inbox: inbox);
  }

  void _listenRealtime({
    required AuthSession session,
    required InboxRepository inbox,
  }) {
    _realtimeSubscription = inbox
        .watch(session: session)
        .listen(
          _onRealtimeEvent,
          onError: (Object error, StackTrace stackTrace) {
            _setConnectionStatus(InboxConnectionStatus.disconnected);
          },
          onDone: () {
            _setConnectionStatus(InboxConnectionStatus.disconnected);
          },
        );
  }

  void _onRealtimeEvent(InboxRealtimeEvent event) {
    final InboxViewState? current = state.value;
    if (current == null) return;
    switch (event) {
      case InboxConnectionChanged(:final status):
        _setConnectionStatus(status);
      case InboxPostChanged(:final postId, :final candidate):
        if (_busy) {
          _pendingRealtimePostChanges.add(event);
          return;
        }
        state = AsyncData(
          current.copyWith(
            snapshot: applyInboxPostChange(
              snapshot: current.snapshot,
              postId: postId,
              candidate: candidate,
            ),
          ),
        );
      case InboxRefreshRequired():
        _realtimeRefreshQueued = true;
        unawaited(_refreshFromRealtime());
    }
  }

  void _setConnectionStatus(InboxConnectionStatus status) {
    final InboxViewState? current = state.value;
    if (current == null || current.connectionStatus == status) return;
    state = AsyncData(current.copyWith(connectionStatus: status));
  }

  Future<void> _refreshFromRealtime() async {
    if (_busy || !_realtimeRefreshQueued) return;
    _realtimeRefreshQueued = false;
    await refresh();
  }

  Future<void> refresh() async {
    final InboxViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if (_busy || current == null || session == null || inbox == null) return;
    _busy = true;
    state = AsyncData(
      current.copyWith(isRefreshing: true, refreshFailed: false),
    );
    try {
      final InboxSnapshot snapshot = await _cancellation.run(
        () => inbox.load(session: session),
      );
      final InboxViewState latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          snapshot: snapshot,
          isRefreshing: false,
          refreshFailed: false,
        ),
      );
    } on Object {
      if (!_cancellation.isCancelled) {
        final InboxViewState latest = state.value ?? current;
        state = AsyncData(
          latest.copyWith(isRefreshing: false, refreshFailed: true),
        );
      }
    } finally {
      _finishBusyOperation();
    }
  }

  Future<bool> postpone(InboxItem item) => _move(item, toPostponed: true);
  Future<bool> remove(InboxItem item) => _move(item, toPostponed: false);

  Future<bool> markRead(InboxItem item) async {
    final InboxViewState? current = state.value;
    final AuthSession? session = _session;
    final InboxRepository? inbox = _inbox;
    if (_busy || current == null || session == null || inbox == null) {
      return false;
    }
    _busy = true;
    try {
      await inbox.markRead(session: session, item: item);
      final List<InboxItem> newItems = current.snapshot.newItems
          .where((InboxItem candidate) => !_isReadBy(candidate, item))
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
          isRefreshing: false,
          refreshFailed: false,
        ),
      );
      return true;
    } on Object {
      return false;
    } finally {
      _finishBusyOperation();
    }
  }

  bool _isReadBy(InboxItem candidate, InboxItem readItem) {
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
    if (_busy || current == null || session == null || postponed == null) {
      return false;
    }
    _busy = true;
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
          isRefreshing: false,
          refreshFailed: false,
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
    _busy = false;
    final InboxViewState? current = state.value;
    if (current != null && _pendingRealtimePostChanges.isNotEmpty) {
      var snapshot = current.snapshot;
      for (final InboxPostChanged change in _pendingRealtimePostChanges) {
        snapshot = applyInboxPostChange(
          snapshot: snapshot,
          postId: change.postId,
          candidate: change.candidate,
        );
      }
      _pendingRealtimePostChanges.clear();
      state = AsyncData(current.copyWith(snapshot: snapshot));
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
