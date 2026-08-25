import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final class ThreadViewState {
  const ThreadViewState({
    required this.thread,
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  final MessageThread thread;
  final bool isRefreshing;
  final bool refreshFailed;

  ThreadViewState copyWith({
    MessageThread? thread,
    bool? isRefreshing,
    bool? refreshFailed,
  }) => ThreadViewState(
    thread: thread ?? this.thread,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
  );
}

final class ThreadController extends AsyncNotifier<ThreadViewState> {
  ThreadController(
    this.rootPostId,
    this._sessionProvider,
    this._repositoryProvider,
  );

  final String rootPostId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<ThreadRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  ThreadRepository? _repository;
  bool _refreshing = false;

  @override
  Future<ThreadViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    _session = null;
    _repository = null;
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) {
      return ThreadViewState(thread: MessageThread(rootPostId: rootPostId));
    }
    final ThreadRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    final MessageThread thread = await cancellation.run(
      () => repository.load(session: session, rootPostId: rootPostId),
    );
    return ThreadViewState(thread: thread);
  }

  Future<void> retry() async {
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (_refreshing || session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    _refreshing = true;
    final ThreadViewState? current = state.value;
    if (current == null) {
      state = const AsyncLoading<ThreadViewState>();
    } else {
      state = AsyncData(
        current.copyWith(isRefreshing: true, refreshFailed: false),
      );
    }
    try {
      final MessageThread thread = await cancellation.run(
        () => repository.load(session: session, rootPostId: rootPostId),
      );
      state = AsyncData(ThreadViewState(thread: thread));
    } on Object catch (error, stackTrace) {
      if (cancellation.isCancelled) return;
      final ThreadViewState? latest = state.value;
      state = latest == null
          ? AsyncError<ThreadViewState>(error, stackTrace)
          : AsyncData(
              latest.copyWith(isRefreshing: false, refreshFailed: true),
            );
    } finally {
      _refreshing = false;
    }
  }
}
