import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/data/secure_credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/posts/data/api_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final Provider<ChannelPostRepository> channelPostRepositoryProvider =
    Provider<ChannelPostRepository>(
      (Ref ref) =>
          ApiChannelPostRepository(credentialStore: SecureCredentialStore()),
    );

final class ChannelPostsViewState {
  const ChannelPostsViewState({
    required this.posts,
    required this.hasOlder,
    this.replySummaries = const <String, ChannelReplySummary>{},
    this.beforePostId,
    this.isLoadingOlder = false,
    this.loadFailed = false,
  });

  final List<ChannelPost> posts;
  final bool hasOlder;
  final Map<String, ChannelReplySummary> replySummaries;
  final String? beforePostId;
  final bool isLoadingOlder;
  final bool loadFailed;

  ChannelPostsViewState copyWith({
    List<ChannelPost>? posts,
    bool? hasOlder,
    Map<String, ChannelReplySummary>? replySummaries,
    String? beforePostId,
    bool? isLoadingOlder,
    bool? loadFailed,
  }) => ChannelPostsViewState(
    posts: posts ?? this.posts,
    hasOlder: hasOlder ?? this.hasOlder,
    replySummaries: replySummaries ?? this.replySummaries,
    beforePostId: beforePostId ?? this.beforePostId,
    isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
    loadFailed: loadFailed ?? this.loadFailed,
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
  AuthSession? _session;
  ChannelPostRepository? _repository;
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
    return _loadLatest(session, repository);
  }

  Future<void> retry() async {
    final AuthSession? session = _session;
    final ChannelPostRepository? repository = _repository;
    if (session == null || repository == null) return;
    state = const AsyncLoading<ChannelPostsViewState>();
    state = await AsyncValue.guard(() => _loadLatest(session, repository));
  }

  Future<void> loadOlder() async {
    final AuthSession? session = _session;
    final ChannelPostRepository? repository = _repository;
    final ChannelPostsViewState? current = state.value;
    final String? beforePostId = current?.beforePostId;
    if (_olderRunning ||
        session == null ||
        repository == null ||
        current == null ||
        beforePostId == null ||
        !current.hasOlder) {
      return;
    }
    _olderRunning = true;
    state = AsyncData(
      current.copyWith(isLoadingOlder: true, loadFailed: false),
    );
    try {
      final ChannelPostPage page = await repository.loadOlder(
        session: session,
        channelId: channelId,
        beforePostId: beforePostId,
      );
      final ChannelPostsViewState? latest = state.value;
      if (latest == null) return;
      final Map<String, ChannelReplySummary> replySummaries =
          _mergeReplySummaries(latest.replySummaries, page.replySummaries);
      state = AsyncData(
        ChannelPostsViewState(
          posts: _applyReplySummaries(
            _mergePosts(latest.posts, page.posts),
            replySummaries,
          ),
          hasOlder: page.hasOlder,
          replySummaries: replySummaries,
          beforePostId: page.beforePostId,
        ),
      );
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

  Future<ChannelPostsViewState> _loadLatest(
    AuthSession session,
    ChannelPostRepository repository,
  ) async {
    final ChannelPostPage page = await repository.loadLatest(
      session: session,
      channelId: channelId,
    );
    return ChannelPostsViewState(
      posts: page.posts,
      hasOlder: page.hasOlder,
      replySummaries: page.replySummaries,
      beforePostId: page.beforePostId,
    );
  }

  static List<ChannelPost> _mergePosts(
    List<ChannelPost> current,
    List<ChannelPost> incoming,
  ) {
    final Map<String, ChannelPost> byId = <String, ChannelPost>{
      for (final ChannelPost post in current) post.id: post,
    };
    for (final ChannelPost post in incoming) {
      final ChannelPost? existing = byId[post.id];
      byId[post.id] = existing == null
          ? post
          : post.withThreadSummary(
              replyCount: existing.replyCount > post.replyCount
                  ? existing.replyCount
                  : post.replyCount,
              lastReplyAt: _latest(existing.lastReplyAt, post.lastReplyAt),
            );
    }
    final List<ChannelPost> result = byId.values.toList(growable: false)
      ..sort((ChannelPost a, ChannelPost b) {
        final int byTime = a.sentAt.compareTo(b.sentAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return List<ChannelPost>.unmodifiable(result);
  }

  static Map<String, ChannelReplySummary> _mergeReplySummaries(
    Map<String, ChannelReplySummary> current,
    Map<String, ChannelReplySummary> incoming,
  ) {
    final Set<String> rootIds = <String>{...current.keys, ...incoming.keys};
    return Map<String, ChannelReplySummary>.unmodifiable(
      <String, ChannelReplySummary>{
        for (final String rootId in rootIds)
          rootId: ChannelReplySummary(
            replyIds: Set<String>.unmodifiable(<String>{
              ...?current[rootId]?.replyIds,
              ...?incoming[rootId]?.replyIds,
            }),
            lastReplyAt: _latest(
              current[rootId]?.lastReplyAt,
              incoming[rootId]?.lastReplyAt,
            ),
          ),
      },
    );
  }

  static List<ChannelPost> _applyReplySummaries(
    List<ChannelPost> posts,
    Map<String, ChannelReplySummary> summaries,
  ) => List<ChannelPost>.unmodifiable(
    posts.map((ChannelPost post) {
      final ChannelReplySummary? summary = summaries[post.id];
      if (summary == null) return post;
      final int observedCount = summary.replyIds.length;
      return post.withThreadSummary(
        replyCount: post.replyCount > observedCount
            ? post.replyCount
            : observedCount,
        lastReplyAt: _latest(post.lastReplyAt, summary.lastReplyAt),
      );
    }),
  );

  static DateTime? _latest(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }
}
