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
    this.total = 0,
    this.totalUnreadThreads = 0,
    this.totalUnreadMentions = 0,
    this.hasMore = false,
    this.nextBefore,
    this.paginationStatus = const OperationStatus.idle(),
    this.refreshStatus = const OperationStatus.idle(),
  });

  final List<FollowedThread> items;
  final int total;
  final int totalUnreadThreads;
  final int totalUnreadMentions;
  final bool hasMore;
  final String? nextBefore;
  final OperationStatus paginationStatus;
  final OperationStatus refreshStatus;

  FollowedThreadsViewState copyWith({
    List<FollowedThread>? items,
    int? total,
    int? totalUnreadThreads,
    int? totalUnreadMentions,
    bool? hasMore,
    String? nextBefore,
    OperationStatus? paginationStatus,
    OperationStatus? refreshStatus,
  }) => FollowedThreadsViewState(
    items: items ?? this.items,
    total: total ?? this.total,
    totalUnreadThreads: totalUnreadThreads ?? this.totalUnreadThreads,
    totalUnreadMentions: totalUnreadMentions ?? this.totalUnreadMentions,
    hasMore: hasMore ?? this.hasMore,
    nextBefore: nextBefore ?? this.nextBefore,
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

  final String teamId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<ThreadRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  ThreadRepository? _repository;
  StreamSubscription<FollowedThreadsRealtimeEvent>? _realtimeSubscription;
  bool _realtimeRefreshPending = false;
  bool _realtimeRefreshRunning = false;

  @override
  Future<FollowedThreadsViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(() {
      cancellation.cancel();
      unawaited(_realtimeSubscription?.cancel());
    });
    _session = null;
    _repository = null;
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) return const FollowedThreadsViewState();
    final ThreadRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    _startRealtime(session, repository);
    return _stateFromPage(
      await cancellation.run(
        () => repository.loadFollowed(session: session, teamId: teamId),
      ),
    );
  }

  void _startRealtime(AuthSession session, ThreadRepository repository) {
    if (repository is! FollowedThreadsRealtimeRepository) return;
    final FollowedThreadsRealtimeRepository realtimeRepository =
        repository as FollowedThreadsRealtimeRepository;
    _realtimeSubscription = realtimeRepository
        .watchFollowedThreads(session: session, teamId: teamId)
        .listen(
          (_) => _requestRealtimeRefresh(),
          onError: (_, _) => _requestRealtimeRefresh(),
        );
  }

  void _requestRealtimeRefresh() {
    _realtimeRefreshPending = true;
    _drainRealtimeRefresh();
  }

  void _drainRealtimeRefresh() {
    final FollowedThreadsViewState? current = state.value;
    if (_realtimeRefreshRunning ||
        current == null ||
        current.refreshStatus is OperationInProgress ||
        current.paginationStatus is OperationInProgress) {
      return;
    }
    unawaited(_refreshFromRealtime());
  }

  Future<void> _refreshFromRealtime() async {
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (session == null || repository == null || _realtimeRefreshRunning) {
      return;
    }
    _realtimeRefreshRunning = true;
    try {
      while (_realtimeRefreshPending && !_cancellation.isCancelled) {
        _realtimeRefreshPending = false;
        final FollowedThreadsViewState? current = state.value;
        if (current == null) continue;
        try {
          state = AsyncData(
            _stateFromPage(
              await _cancellation.run(
                () => repository.loadFollowed(session: session, teamId: teamId),
              ),
            ),
          );
        } on Object {
          // Preserve useful data. A later socket event, reconnect, or manual
          // refresh reconciles a transient failure.
        }
      }
    } finally {
      _realtimeRefreshRunning = false;
    }
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
    final RequestCancellation cancellation = _cancellation;
    state = AsyncData(
      current.copyWith(refreshStatus: const OperationStatus.inProgress()),
    );
    try {
      state = AsyncData(
        _stateFromPage(
          await cancellation.run(
            () => repository.loadFollowed(session: session, teamId: teamId),
          ),
        ),
      );
    } on Object catch (error) {
      if (cancellation.isCancelled) return;
      state = AsyncData(
        current.copyWith(refreshStatus: OperationStatus.failed(error)),
      );
    } finally {
      _drainRealtimeRefresh();
    }
  }

  Future<void> loadMore() async {
    final FollowedThreadsViewState? current = state.value;
    if (current == null ||
        current.refreshStatus is OperationInProgress ||
        current.paginationStatus is OperationInProgress ||
        !current.hasMore ||
        current.nextBefore == null) {
      return;
    }
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    state = AsyncData(
      current.copyWith(paginationStatus: const OperationStatus.inProgress()),
    );
    try {
      final FollowedThreadsPage page = await cancellation.run(
        () => repository.loadFollowed(
          session: session,
          teamId: teamId,
          before: current.nextBefore,
        ),
      );
      final Map<String, FollowedThread> merged = <String, FollowedThread>{
        for (final FollowedThread item in current.items) item.id: item,
        for (final FollowedThread item in page.items) item.id: item,
      };
      final bool cursorAdvanced =
          page.nextBefore != null && page.nextBefore != current.nextBefore;
      state = AsyncData(
        FollowedThreadsViewState(
          items: List<FollowedThread>.unmodifiable(merged.values),
          total: page.total,
          totalUnreadThreads: page.totalUnreadThreads,
          totalUnreadMentions: page.totalUnreadMentions,
          hasMore: page.hasMore && cursorAdvanced && merged.length < page.total,
          nextBefore: cursorAdvanced ? page.nextBefore : current.nextBefore,
        ),
      );
    } on Object catch (error) {
      if (cancellation.isCancelled) return;
      state = AsyncData(
        current.copyWith(paginationStatus: OperationStatus.failed(error)),
      );
    } finally {
      _drainRealtimeRefresh();
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
    if (readThread == null || !readThread.isUnread) return;
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
        items: page.items,
        total: page.total,
        totalUnreadThreads: page.totalUnreadThreads,
        totalUnreadMentions: page.totalUnreadMentions,
        hasMore:
            page.hasMore &&
            page.nextBefore != null &&
            page.items.length < page.total,
        nextBefore: page.nextBefore,
      );
}
