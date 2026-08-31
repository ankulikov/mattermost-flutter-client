import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/core/utils/date_time_utils.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';

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

final class ChannelPostsController
    extends AsyncNotifier<ChannelPostsViewState> {
  ChannelPostsController(
    this.channelId,
    this._sessionProvider,
    this._repositoryProvider,
  );

  final String channelId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<PostRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  PostRepository? _repository;
  bool _olderRunning = false;
  bool _sendRunning = false;
  final Set<String> _reactionRequests = <String>{};

  @override
  Future<ChannelPostsViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    _session = null;
    _repository = null;
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) {
      return const ChannelPostsViewState(
        posts: <ChannelPost>[],
        hasOlder: false,
      );
    }
    final PostRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    return cancellation.run(() => _loadLatest(session, repository));
  }

  Future<void> retry() async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    state = const AsyncLoading<ChannelPostsViewState>();
    try {
      state = AsyncData(
        await cancellation.run(() => _loadLatest(session, repository)),
      );
    } on Object catch (error, stackTrace) {
      if (cancellation.isCancelled) return;
      state = AsyncError<ChannelPostsViewState>(error, stackTrace);
    }
  }

  Future<void> loadOlder() async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
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
    final RequestCancellation cancellation = _cancellation;
    _olderRunning = true;
    state = AsyncData(
      current.copyWith(isLoadingOlder: true, loadFailed: false),
    );
    try {
      final ChannelPostPage page = await cancellation.run(
        () => repository.loadOlder(
          session: session,
          channelId: channelId,
          beforePostId: beforePostId,
        ),
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
      if (cancellation.isCancelled) return;
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isLoadingOlder: false, loadFailed: true),
        );
      }
    } finally {
      _olderRunning = false;
      if (!cancellation.isCancelled) {
        final ChannelPostsViewState? latest = state.value;
        if (latest != null && latest.isLoadingOlder) {
          state = AsyncData(latest.copyWith(isLoadingOlder: false));
        }
      }
    }
  }

  Future<ChannelPost> sendText({
    required String message,
    required String pendingPostId,
  }) async {
    final AuthSession? session = _session;
    if (_sendRunning) {
      throw StateError('A channel message is already being sent');
    }
    if (session == null || state.value == null) {
      throw StateError('Channel messages are not ready');
    }
    _sendRunning = true;
    try {
      final ChannelPost sent = await _cancellation.run(
        () => _repository!.sendText(
          session: session,
          channelId: channelId,
          message: message,
          pendingPostId: pendingPostId,
        ),
      );
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            posts: _mergePosts(latest.posts, <ChannelPost>[sent]),
          ),
        );
      }
      return sent;
    } finally {
      _sendRunning = false;
    }
  }

  Future<bool> toggleReaction({
    required String postId,
    required String emojiName,
  }) async {
    final AuthSession? session = _session;
    final ChannelPostsViewState? current = state.value;
    final String requestKey = '$postId\u0000$emojiName';
    if (session == null ||
        current == null ||
        !_reactionRequests.add(requestKey)) {
      return false;
    }
    final int postIndex = current.posts.indexWhere(
      (ChannelPost post) => post.id == postId,
    );
    if (postIndex < 0) {
      _reactionRequests.remove(requestKey);
      return false;
    }
    final ChannelPost original = current.posts[postIndex];
    final bool remove = original.reactions.any(
      (PostReaction reaction) =>
          reaction.emojiName == emojiName && reaction.reactedByCurrentUser,
    );
    _replacePost(toggleCurrentUserReaction(original, emojiName));
    try {
      if (remove) {
        await _cancellation.run(
          () => _repository!.removeReaction(
            session: session,
            postId: postId,
            emojiName: emojiName,
          ),
        );
      } else {
        await _cancellation.run(
          () => _repository!.addReaction(
            session: session,
            postId: postId,
            emojiName: emojiName,
          ),
        );
      }
      return true;
    } on Object {
      if (!_cancellation.isCancelled) {
        final ChannelPost? latest = state.value?.posts
            .where((ChannelPost post) => post.id == postId)
            .firstOrNull;
        if (latest != null) {
          _replacePost(latest.withReactions(original.reactions));
        }
      }
      return false;
    } finally {
      _reactionRequests.remove(requestKey);
    }
  }

  void _replacePost(ChannelPost replacement) {
    final ChannelPostsViewState? current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        posts: List<ChannelPost>.unmodifiable(
          current.posts.map(
            (ChannelPost post) =>
                post.id == replacement.id ? replacement : post,
          ),
        ),
      ),
    );
  }

  void recordSentReply(ChannelPost reply) {
    final ChannelPostsViewState? current = state.value;
    if (current == null || reply.rootId.isEmpty) return;
    final ChannelReplySummary? previous = current.replySummaries[reply.rootId];
    final bool wasKnown = previous?.replyIds.contains(reply.id) == true;
    final Map<String, ChannelReplySummary> summaries =
        Map<String, ChannelReplySummary>.unmodifiable(
          <String, ChannelReplySummary>{
            ...current.replySummaries,
            reply.rootId: ChannelReplySummary(
              replyIds: Set<String>.unmodifiable(<String>{
                ...?previous?.replyIds,
                reply.id,
              }),
              lastReplyAt: latestDateTime(previous?.lastReplyAt, reply.sentAt),
            ),
          },
        );
    state = AsyncData(
      current.copyWith(
        posts: List<ChannelPost>.unmodifiable(
          current.posts.map((ChannelPost post) {
            if (post.id != reply.rootId) return post;
            final int incrementedCount = post.replyCount + (wasKnown ? 0 : 1);
            final int observedCount = summaries[reply.rootId]!.replyIds.length;
            return post.withThreadSummary(
              replyCount: incrementedCount > observedCount
                  ? incrementedCount
                  : observedCount,
              lastReplyAt: latestDateTime(post.lastReplyAt, reply.sentAt),
            );
          }),
        ),
        replySummaries: summaries,
      ),
    );
  }

  Future<ChannelPostsViewState> _loadLatest(
    AuthSession session,
    PostRepository repository,
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
              lastReplyAt: latestDateTime(
                existing.lastReplyAt,
                post.lastReplyAt,
              ),
            );
    }
    final List<ChannelPost> result = byId.values.toList(growable: false)
      ..sort(compareMessagesBySentAt);
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
            lastReplyAt: latestDateTime(
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
        lastReplyAt: latestDateTime(post.lastReplyAt, summary.lastReplyAt),
      );
    }),
  );
}
