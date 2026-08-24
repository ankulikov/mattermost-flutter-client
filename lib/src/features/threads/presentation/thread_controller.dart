import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/database/database_provider.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_thread_repository.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final Provider<ThreadRepository> threadRepositoryProvider =
    Provider<ThreadRepository>((Ref ref) {
      final ApiThreadRepository repository = ApiThreadRepository(
        credentialStore: SecureCredentialStore(),
        database: ref.watch(appDatabaseProvider),
      );
      ref.onDispose(() => unawaited(repository.close()));
      return repository;
    });

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
  StreamSubscription<MessageThread>? _subscription;
  bool _refreshing = false;

  @override
  Future<ThreadViewState> build() async {
    final AuthSession? session = ref.watch(
      authControllerProvider.select((state) => state.session),
    );
    if (session == null) {
      return ThreadViewState(thread: MessageThread(rootPostId: rootPostId));
    }
    final ThreadRepository repository = ref.watch(threadRepositoryProvider);
    _session = session;
    _repository = repository;
    final MessageThread cached = await repository.read(
      accountId: session.accountId,
      rootPostId: rootPostId,
    );
    _subscription = repository
        .watch(accountId: session.accountId, rootPostId: rootPostId)
        .listen(_onCacheChanged);
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    unawaited(Future<void>(_refresh));
    return ThreadViewState(thread: cached, isRefreshing: true);
  }

  Future<void> retry() => _refresh();

  Future<void> _refresh() async {
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    if (_refreshing || session == null || repository == null) return;
    _refreshing = true;
    final ThreadViewState? current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(isRefreshing: true, refreshFailed: false),
      );
    }
    try {
      await repository.refresh(session: session, rootPostId: rootPostId);
      final ThreadViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isRefreshing: false, refreshFailed: false),
        );
      }
    } on Object {
      final ThreadViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isRefreshing: false, refreshFailed: true),
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  void _onCacheChanged(MessageThread thread) {
    final ThreadViewState? current = state.value;
    if (current != null) state = AsyncData(current.copyWith(thread: thread));
  }
}
