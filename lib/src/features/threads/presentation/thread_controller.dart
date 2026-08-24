import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_thread_repository.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final Provider<ThreadRepository> threadRepositoryProvider =
    Provider<ThreadRepository>(
      (Ref ref) =>
          ApiThreadRepository(credentialStore: SecureCredentialStore()),
    );

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

final threadProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadController, ThreadViewState, String>(ThreadController.new);

final class ThreadController extends AsyncNotifier<ThreadViewState> {
  ThreadController(this.rootPostId);

  final String rootPostId;
  AuthSession? _session;
  ThreadRepository? _repository;
  bool _refreshing = false;

  @override
  Future<ThreadViewState> build() async {
    final AuthSession? session = ref.watch(
      authControllerProvider.select((AuthState state) => state.session),
    );
    if (session == null) {
      return ThreadViewState(thread: MessageThread(rootPostId: rootPostId));
    }
    final ThreadRepository repository = ref.watch(threadRepositoryProvider);
    _session = session;
    _repository = repository;
    final MessageThread thread = await repository.load(
      session: session,
      rootPostId: rootPostId,
    );
    return ThreadViewState(thread: thread);
  }

  Future<void> retry() async {
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (_refreshing || session == null || repository == null) return;
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
      final MessageThread thread = await repository.load(
        session: session,
        rootPostId: rootPostId,
      );
      state = AsyncData(ThreadViewState(thread: thread));
    } on Object catch (error, stackTrace) {
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
