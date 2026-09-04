import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

final class InboxViewState {
  const InboxViewState({
    required this.snapshot,
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  final InboxSnapshot snapshot;
  final bool isRefreshing;
  final bool refreshFailed;

  InboxViewState copyWith({
    InboxSnapshot? snapshot,
    bool? isRefreshing,
    bool? refreshFailed,
  }) => InboxViewState(
    snapshot: snapshot ?? this.snapshot,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
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
  bool _busy = false;

  @override
  Future<InboxViewState> build() async {
    _cancellation = RequestCancellation();
    ref.onDispose(_cancellation.cancel);
    _session = ref.watch(_sessionProvider);
    if (_session == null) {
      return InboxViewState(snapshot: InboxSnapshot());
    }
    _inbox = ref.watch(_inboxProvider);
    _postponed = ref.watch(_postponedProvider);
    return InboxViewState(
      snapshot: await _cancellation.run(() => _inbox!.load(session: _session!)),
    );
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
      state = AsyncData(
        InboxViewState(
          snapshot: await _cancellation.run(() => inbox.load(session: session)),
        ),
      );
    } on Object {
      if (!_cancellation.isCancelled) {
        state = AsyncData(
          current.copyWith(isRefreshing: false, refreshFailed: true),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<bool> postpone(InboxItem item) => _move(item, toPostponed: true);
  Future<bool> remove(InboxItem item) => _move(item, toPostponed: false);

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
        newItems.removeWhere((InboxItem value) => value.key == item.key);
        postponedItems.add(_withPostponedAt(item, now));
      } else {
        postponedItems.removeWhere((InboxItem value) => value.key == item.key);
      }
      state = AsyncData(
        InboxViewState(
          snapshot: InboxSnapshot(
            newItems: newItems,
            postponedItems: postponedItems,
            builtAt: current.snapshot.builtAt,
            hasIncompleteMentionReconstruction:
                current.snapshot.hasIncompleteMentionReconstruction,
          ),
        ),
      );
      return true;
    } on Object {
      return false;
    } finally {
      _busy = false;
    }
  }

  InboxItem _withPostponedAt(InboxItem item, DateTime at) => switch (item) {
    ThreadInboxItem() => ThreadInboxItem(thread: item.thread, postponedAt: at),
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
