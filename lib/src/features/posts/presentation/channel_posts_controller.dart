import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/database/database_provider.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/posts/data/api_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/data/channel_post_store.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final Provider<ChannelPostStore> channelPostStoreProvider =
    Provider<ChannelPostStore>((Ref ref) {
      final ChannelPostStore store = ChannelPostStore(
        ref.watch(appDatabaseProvider),
      );
      ref.onDispose(() => unawaited(store.close()));
      return store;
    });

final Provider<ChannelPostRepository> channelPostRepositoryProvider =
    Provider<ChannelPostRepository>(
      (Ref ref) => ApiChannelPostRepository(
        credentialStore: SecureCredentialStore(),
        store: ref.watch(channelPostStoreProvider),
      ),
    );

final class ChannelPostsViewState {
  const ChannelPostsViewState({
    required this.posts,
    required this.hasOlder,
    this.isRefreshing = false,
    this.isLoadingOlder = false,
    this.hasRecentMessages = false,
    this.loadFailed = false,
    this.recentCutoff,
    this.idsAtOpen = const <String>{},
  });

  final List<ChannelPost> posts;
  final bool hasOlder;
  final bool isRefreshing;
  final bool isLoadingOlder;
  final bool hasRecentMessages;
  final bool loadFailed;
  final DateTime? recentCutoff;
  final Set<String> idsAtOpen;

  List<ChannelPost> get visiblePosts {
    final DateTime? cutoff = recentCutoff;
    if (cutoff == null) return posts;
    return posts
        .where(
          (ChannelPost post) =>
              idsAtOpen.contains(post.id) || post.sentAt.isBefore(cutoff),
        )
        .toList(growable: false);
  }

  ChannelPostsViewState copyWith({
    List<ChannelPost>? posts,
    bool? hasOlder,
    bool? isRefreshing,
    bool? isLoadingOlder,
    bool? hasRecentMessages,
    bool? loadFailed,
    DateTime? recentCutoff,
    bool clearRecentCutoff = false,
    Set<String>? idsAtOpen,
  }) => ChannelPostsViewState(
    posts: posts ?? this.posts,
    hasOlder: hasOlder ?? this.hasOlder,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
    hasRecentMessages: hasRecentMessages ?? this.hasRecentMessages,
    loadFailed: loadFailed ?? this.loadFailed,
    recentCutoff: clearRecentCutoff ? null : recentCutoff ?? this.recentCutoff,
    idsAtOpen: idsAtOpen ?? this.idsAtOpen,
  );
}

final channelPostsProvider = AsyncNotifierProvider.autoDispose
    .family<ChannelPostsController, ChannelPostsViewState, String>(
      ChannelPostsController.new,
    );

final class ChannelPostsController
    extends AsyncNotifier<ChannelPostsViewState> {
  ChannelPostsController(this.channelId);

  final String channelId;
  StreamSubscription<ChannelPostSnapshot>? _subscription;
  AuthSession? _session;
  ChannelPostRepository? _repository;
  bool _refreshRunning = false;
  bool _olderRunning = false;

  @override
  Future<ChannelPostsViewState> build() async {
    final AuthSession? session = ref.watch(
      authControllerProvider.select((AuthState value) => value.session),
    );
    if (session == null) {
      return const ChannelPostsViewState(
        posts: <ChannelPost>[],
        hasOlder: false,
      );
    }
    final ChannelPostRepository repository = ref.watch(
      channelPostRepositoryProvider,
    );
    _session = session;
    _repository = repository;
    final ChannelPostSnapshot cached = await repository.read(
      accountId: session.accountId,
      channelId: channelId,
    );
    final Set<String> idsAtOpen = cached.posts
        .map((ChannelPost post) => post.id)
        .toSet();
    final DateTime? cutoff = cached.posts.isEmpty
        ? null
        : cached.posts.last.sentAt;
    final ChannelPostsViewState initial = ChannelPostsViewState(
      posts: cached.posts,
      hasOlder: cached.hasOlder,
      isRefreshing: true,
      recentCutoff: cutoff,
      idsAtOpen: idsAtOpen,
    );
    _subscription = repository
        .watch(accountId: session.accountId, channelId: channelId)
        .listen(_onCacheChanged);
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    unawaited(Future<void>(_refreshLatest));
    return initial;
  }

  Future<void> retry() => _refreshLatest();

  Future<void> loadOlder() async {
    final AuthSession? session = _session;
    final ChannelPostRepository? repository = _repository;
    final ChannelPostsViewState? current = state.value;
    if (_olderRunning ||
        session == null ||
        repository == null ||
        current == null ||
        !current.hasOlder) {
      return;
    }
    _olderRunning = true;
    state = AsyncData(
      current.copyWith(isLoadingOlder: true, loadFailed: false),
    );
    try {
      await repository.loadOlder(session: session, channelId: channelId);
    } on Object {
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isLoadingOlder: false, loadFailed: true),
        );
      }
    } finally {
      _olderRunning = false;
      final ChannelPostsViewState? latest = state.value;
      if (latest != null && latest.isLoadingOlder) {
        state = AsyncData(latest.copyWith(isLoadingOlder: false));
      }
    }
  }

  void showRecentMessages() {
    final ChannelPostsViewState? current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        hasRecentMessages: false,
        clearRecentCutoff: true,
        idsAtOpen: const <String>{},
      ),
    );
  }

  Future<void> _refreshLatest() async {
    final AuthSession? session = _session;
    final ChannelPostRepository? repository = _repository;
    if (_refreshRunning || session == null || repository == null) return;
    _refreshRunning = true;
    final ChannelPostsViewState? current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(isRefreshing: true, loadFailed: false),
      );
    }
    try {
      final ChannelPostRefreshResult result = await repository.refreshLatest(
        session: session,
        channelId: channelId,
      );
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        final bool holdRecent =
            latest.recentCutoff != null && result.newPostIds.isNotEmpty;
        state = AsyncData(
          latest.copyWith(
            isRefreshing: false,
            hasRecentMessages: holdRecent,
            clearRecentCutoff: !holdRecent,
          ),
        );
      }
    } on Object {
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isRefreshing: false, loadFailed: true),
        );
      }
    } finally {
      _refreshRunning = false;
    }
  }

  void _onCacheChanged(ChannelPostSnapshot snapshot) {
    final ChannelPostsViewState? current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(posts: snapshot.posts, hasOlder: snapshot.hasOlder),
    );
  }
}
