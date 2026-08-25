import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_threads_repository.dart';

final class FollowedThreadsViewState {
  const FollowedThreadsViewState({
    this.items = const <FollowedThread>[],
    this.total = 0,
    this.totalUnreadThreads = 0,
    this.totalUnreadMentions = 0,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  final List<FollowedThread> items;
  final int total;
  final int totalUnreadThreads;
  final int totalUnreadMentions;
  final bool isLoadingMore;
  final bool loadMoreFailed;
  final bool isRefreshing;
  final bool refreshFailed;

  bool get hasMore => items.length < total;

  FollowedThreadsViewState copyWith({
    List<FollowedThread>? items,
    int? total,
    int? totalUnreadThreads,
    int? totalUnreadMentions,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    bool? isRefreshing,
    bool? refreshFailed,
  }) => FollowedThreadsViewState(
    items: items ?? this.items,
    total: total ?? this.total,
    totalUnreadThreads: totalUnreadThreads ?? this.totalUnreadThreads,
    totalUnreadMentions: totalUnreadMentions ?? this.totalUnreadMentions,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
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
  final Provider<FollowedThreadsRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  FollowedThreadsRepository? _repository;
  bool _busy = false;

  @override
  Future<FollowedThreadsViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    _session = null;
    _repository = null;
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) return const FollowedThreadsViewState();
    final FollowedThreadsRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    return _stateFromPage(
      await cancellation.run(
        () => repository.loadPage(session: session, teamId: teamId),
      ),
    );
  }

  Future<void> refresh() async {
    final FollowedThreadsViewState? current = state.value;
    if (_busy || current == null) return;
    final AuthSession? session = _session;
    final FollowedThreadsRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    _busy = true;
    state = AsyncData(
      current.copyWith(isRefreshing: true, refreshFailed: false),
    );
    try {
      state = AsyncData(
        _stateFromPage(
          await cancellation.run(
            () => repository.loadPage(session: session, teamId: teamId),
          ),
        ),
      );
    } on Object {
      if (cancellation.isCancelled) return;
      state = AsyncData(
        current.copyWith(isRefreshing: false, refreshFailed: true),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    final FollowedThreadsViewState? current = state.value;
    if (_busy || current == null || !current.hasMore || current.items.isEmpty) {
      return;
    }
    final AuthSession? session = _session;
    final FollowedThreadsRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    _busy = true;
    state = AsyncData(
      current.copyWith(isLoadingMore: true, loadMoreFailed: false),
    );
    try {
      final FollowedThreadsPage page = await cancellation.run(
        () => repository.loadPage(
          session: session,
          teamId: teamId,
          before: current.items.last.id,
        ),
      );
      final Map<String, FollowedThread> merged = <String, FollowedThread>{
        for (final FollowedThread item in current.items) item.id: item,
        for (final FollowedThread item in page.items) item.id: item,
      };
      state = AsyncData(
        FollowedThreadsViewState(
          items: List<FollowedThread>.unmodifiable(merged.values),
          total: page.total,
          totalUnreadThreads: page.totalUnreadThreads,
          totalUnreadMentions: page.totalUnreadMentions,
        ),
      );
    } on Object {
      if (cancellation.isCancelled) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    } finally {
      _busy = false;
    }
  }

  static FollowedThreadsViewState _stateFromPage(FollowedThreadsPage page) =>
      FollowedThreadsViewState(
        items: page.items,
        total: page.total,
        totalUnreadThreads: page.totalUnreadThreads,
        totalUnreadMentions: page.totalUnreadMentions,
      );
}
