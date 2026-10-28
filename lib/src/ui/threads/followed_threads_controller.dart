import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';

final class FollowedThreadsViewState {
  const FollowedThreadsViewState({
    this.items = const <FollowedThread>[],
    this.page = 0,
    this.total = 0,
    this.paginationComplete = false,
    this.totalUnreadThreads = 0,
    this.totalUnreadMentions = 0,
    this.paginationStatus = const OperationStatus.idle(),
    this.refreshStatus = const OperationStatus.idle(),
  });

  final List<FollowedThread> items;

  /// Last successfully loaded page index, used only for view state.
  final int page;
  final int total;
  final bool paginationComplete;
  final int totalUnreadThreads;
  final int totalUnreadMentions;
  final OperationStatus paginationStatus;
  final OperationStatus refreshStatus;

  bool get hasMore => !paginationComplete && items.length < total;

  FollowedThreadsViewState copyWith({
    List<FollowedThread>? items,
    int? page,
    int? total,
    bool? paginationComplete,
    int? totalUnreadThreads,
    int? totalUnreadMentions,
    OperationStatus? paginationStatus,
    OperationStatus? refreshStatus,
  }) => FollowedThreadsViewState(
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    paginationComplete: paginationComplete ?? this.paginationComplete,
    totalUnreadThreads: totalUnreadThreads ?? this.totalUnreadThreads,
    totalUnreadMentions: totalUnreadMentions ?? this.totalUnreadMentions,
    paginationStatus: paginationStatus ?? this.paginationStatus,
    refreshStatus: refreshStatus ?? this.refreshStatus,
  );
}

final class FollowedThreadsController
    extends AsyncNotifier<FollowedThreadsViewState> {
  FollowedThreadsController(
    this.teamId,
    this._sessionProvider,
    this._repositoryProvider,
  );

  static const int pageSize = 60;

  final String teamId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<ThreadRepository> _repositoryProvider;
  RequestCancellation? _cancellation;
  StreamSubscription<void>? _realtimeSubscription;
  bool _refreshPending = false;
  AuthSession? _session;
  ThreadRepository? _repository;

  @override
  Future<FollowedThreadsViewState> build() async {
    _cancellation?.cancel();
    _realtimeSubscription?.cancel().ignore();
    _refreshPending = false;
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    _session = null;
    _repository = null;
    if (teamId.isEmpty) return const FollowedThreadsViewState();
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) return const FollowedThreadsViewState();
    final ThreadRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    final StreamSubscription<void> realtimeSubscription = repository
        .watchFollowed(session: session, teamId: teamId)
        .listen(
          (_) => _requestRealtimeRefresh(),
          onError: (Object _) {
            _requestRealtimeRefresh();
          },
        );
    _realtimeSubscription = realtimeSubscription;
    ref.onDispose(() => realtimeSubscription.cancel().ignore());
    final FollowedThreadsPage page = await cancellation.run(
      () => repository.loadFollowed(
        session: session,
        teamId: teamId,
        perPage: pageSize,
      ),
    );
    if (_refreshPending && !cancellation.isCancelled) {
      scheduleMicrotask(_drainPendingRefresh);
    }
    return _stateFromPage(page);
  }

  void _requestRealtimeRefresh() {
    _refreshPending = true;
    _drainPendingRefresh();
  }

  void _drainPendingRefresh() {
    if (!_refreshPending || _cancellation?.isCancelled != false) return;
    final FollowedThreadsViewState? current = state.value;
    if (current == null ||
        current.refreshStatus is OperationInProgress ||
        current.paginationStatus is OperationInProgress) {
      return;
    }
    _refreshPending = false;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    final FollowedThreadsViewState? current = state.value;
    if (current == null ||
        current.refreshStatus is OperationInProgress ||
        current.paginationStatus is OperationInProgress) {
      return;
    }
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation? cancellation = _cancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    state = AsyncData(
      current.copyWith(refreshStatus: const OperationStatus.inProgress()),
    );
    try {
      final FollowedThreadsPage page = await cancellation.run(
        () => repository.loadFollowed(
          session: session,
          teamId: teamId,
          perPage: pageSize,
        ),
      );
      if (cancellation.isCancelled) return;
      state = AsyncData(_stateFromPage(page));
    } on Object catch (error) {
      if (cancellation.isCancelled) return;
      state = AsyncData(
        current.copyWith(refreshStatus: OperationStatus.failed(error)),
      );
    } finally {
      _drainPendingRefresh();
    }
  }

  Future<void> loadMore() async {
    final FollowedThreadsViewState? current = state.value;
    if (current == null ||
        current.refreshStatus is OperationInProgress ||
        current.paginationStatus is OperationInProgress ||
        !current.hasMore ||
        current.items.isEmpty) {
      return;
    }
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation? cancellation = _cancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    state = AsyncData(
      current.copyWith(paginationStatus: const OperationStatus.inProgress()),
    );
    try {
      final FollowedThreadsPage page = await cancellation.run(
        () => repository.loadFollowed(
          session: session,
          teamId: teamId,
          before: current.items.last.id,
          perPage: pageSize,
        ),
      );
      if (cancellation.isCancelled) return;
      final Map<String, FollowedThread> merged = <String, FollowedThread>{
        for (final FollowedThread item in current.items) item.id: item,
        for (final FollowedThread item in page.items) item.id: item,
      };
      if (page.items.isNotEmpty && merged.length == current.items.length) {
        throw StateError(
          'The next followed threads page repeated existing rows',
        );
      }
      state = AsyncData(
        FollowedThreadsViewState(
          items: List<FollowedThread>.unmodifiable(merged.values),
          page: current.page + 1,
          total: page.total,
          paginationComplete: page.items.isEmpty,
          totalUnreadThreads: page.totalUnreadThreads,
          totalUnreadMentions: page.totalUnreadMentions,
        ),
      );
    } on Object catch (error) {
      if (cancellation.isCancelled) return;
      state = AsyncData(
        current.copyWith(paginationStatus: OperationStatus.failed(error)),
      );
    } finally {
      _drainPendingRefresh();
    }
  }

  void recordThreadRead({
    required String rootPostId,
    required DateTime timestamp,
  }) {
    final FollowedThreadsViewState? current = state.value;
    if (current == null) return;
    final FollowedThread? readThread = current.items
        .where((FollowedThread item) => item.id == rootPostId)
        .firstOrNull;
    if (readThread == null ||
        !readThread.isUnread ||
        readThread.lastReplyAt.isAfter(timestamp)) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        items: List<FollowedThread>.unmodifiable(
          current.items.map(
            (FollowedThread item) => item.id == rootPostId
                ? item.copyWith(
                    lastViewedAt: timestamp,
                    unreadReplies: 0,
                    unreadMentions: 0,
                  )
                : item,
          ),
        ),
        totalUnreadThreads: current.totalUnreadThreads > 0
            ? current.totalUnreadThreads - 1
            : 0,
        totalUnreadMentions:
            current.totalUnreadMentions - readThread.unreadMentions > 0
            ? current.totalUnreadMentions - readThread.unreadMentions
            : 0,
      ),
    );
  }

  void removeUnfollowedThread(String rootPostId) {
    final FollowedThreadsViewState? current = state.value;
    if (current == null) return;
    final FollowedThread? removed = current.items
        .where((FollowedThread item) => item.id == rootPostId)
        .firstOrNull;
    if (removed == null) return;
    state = AsyncData(
      current.copyWith(
        items: List<FollowedThread>.unmodifiable(
          current.items.where((FollowedThread item) => item.id != rootPostId),
        ),
        total: current.total > 0 ? current.total - 1 : 0,
        totalUnreadThreads: removed.isUnread && current.totalUnreadThreads > 0
            ? current.totalUnreadThreads - 1
            : current.totalUnreadThreads,
        totalUnreadMentions:
            current.totalUnreadMentions - removed.unreadMentions > 0
            ? current.totalUnreadMentions - removed.unreadMentions
            : 0,
      ),
    );
  }

  static FollowedThreadsViewState _stateFromPage(FollowedThreadsPage page) =>
      FollowedThreadsViewState(
        items: List<FollowedThread>.unmodifiable(
          {for (final FollowedThread item in page.items) item.id: item}.values,
        ),
        total: page.total,
        paginationComplete: page.items.isEmpty,
        totalUnreadThreads: page.totalUnreadThreads,
        totalUnreadMentions: page.totalUnreadMentions,
      );
}
