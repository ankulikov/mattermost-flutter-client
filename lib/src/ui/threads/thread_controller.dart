import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/core/utils/date_time_utils.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

final class ThreadViewState {
  const ThreadViewState({
    required this.thread,
    this.isRefreshing = false,
    this.refreshFailed = false,
    this.isMarkingRead = false,
    this.markReadFailed = false,
    this.isFollowing = false,
    this.isUpdatingFollow = false,
    this.followUpdateFailed = false,
  });

  final MessageThread thread;
  final bool isRefreshing;
  final bool refreshFailed;
  final bool isMarkingRead;
  final bool markReadFailed;
  final bool isFollowing;
  final bool isUpdatingFollow;
  final bool followUpdateFailed;

  ThreadViewState copyWith({
    MessageThread? thread,
    bool? isRefreshing,
    bool? refreshFailed,
    bool? isMarkingRead,
    bool? markReadFailed,
    bool? isFollowing,
    bool? isUpdatingFollow,
    bool? followUpdateFailed,
  }) => ThreadViewState(
    thread: thread ?? this.thread,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    refreshFailed: refreshFailed ?? this.refreshFailed,
    isMarkingRead: isMarkingRead ?? this.isMarkingRead,
    markReadFailed: markReadFailed ?? this.markReadFailed,
    isFollowing: isFollowing ?? this.isFollowing,
    isUpdatingFollow: isUpdatingFollow ?? this.isUpdatingFollow,
    followUpdateFailed: followUpdateFailed ?? this.followUpdateFailed,
  );
}

final class ThreadController extends AsyncNotifier<ThreadViewState> {
  ThreadController(
    this.rootPostId,
    this._sessionProvider,
    this._repositoryProvider,
    this._postRepositoryProvider,
    this._postponedProvider,
    this.teamId,
    this.allowsFollowing,
  );

  final String rootPostId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<ThreadRepository> _repositoryProvider;
  final Provider<PostRepository> _postRepositoryProvider;
  final Provider<PostponedRepository> _postponedProvider;
  final String teamId;
  final bool allowsFollowing;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  ThreadRepository? _repository;
  bool _refreshing = false;
  bool _sendRunning = false;
  bool _markReadRunning = false;
  DateTime? _markedLoadedAt;
  final Set<String> _reactionRequests = <String>{};

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
    final (MessageThread thread, bool isFollowing) = await cancellation.run(
      () async => (
        await repository.load(session: session, rootPostId: rootPostId),
        !allowsFollowing || teamId.isEmpty
            ? false
            : await repository.isFollowing(
                session: session,
                teamId: teamId,
                rootPostId: rootPostId,
              ),
      ),
    );
    return ThreadViewState(thread: thread, isFollowing: isFollowing);
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

  Future<ChannelPost> sendText({
    required String channelId,
    required String message,
    required String pendingPostId,
  }) async {
    final AuthSession? session = _session;
    if (_sendRunning) {
      throw StateError('A thread reply is already being sent');
    }
    if (session == null || state.value?.thread.root == null) {
      throw StateError('Thread is not ready');
    }
    _sendRunning = true;
    try {
      final ChannelPost sent = await _cancellation.run(
        () => ref
            .read(_postRepositoryProvider)
            .sendText(
              session: session,
              channelId: channelId,
              message: message,
              pendingPostId: pendingPostId,
              rootPostId: rootPostId,
            ),
      );
      final ThreadViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(thread: _withSentReply(latest.thread, sent)),
        );
      }
      return sent;
    } finally {
      _sendRunning = false;
    }
  }

  Future<bool> markRead({required String teamId}) async {
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    final ThreadViewState? current = state.value;
    final DateTime? loadedAt = current?.thread.loadedAt;
    if (_markReadRunning ||
        session == null ||
        repository == null ||
        current == null ||
        !current.thread.isComplete ||
        loadedAt == null) {
      return false;
    }
    if (_markedLoadedAt == loadedAt) return true;
    _markReadRunning = true;
    state = AsyncData(
      current.copyWith(isMarkingRead: true, markReadFailed: false),
    );
    try {
      await _cancellation.run(
        () => repository.markRead(
          session: session,
          teamId: teamId,
          rootPostId: rootPostId,
          timestamp: loadedAt,
        ),
      );
      _markedLoadedAt = loadedAt;
      final ThreadViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isMarkingRead: false, markReadFailed: false),
        );
      }
      return true;
    } on Object {
      if (_cancellation.isCancelled) return false;
      final ThreadViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(isMarkingRead: false, markReadFailed: true),
        );
      }
      return false;
    } finally {
      _markReadRunning = false;
    }
  }

  Future<bool> toggleFollowing() async {
    final AuthSession? session = _session;
    final ThreadRepository? repository = _repository;
    final ThreadViewState? current = state.value;
    if (session == null ||
        repository == null ||
        current == null ||
        !allowsFollowing ||
        teamId.isEmpty ||
        current.isUpdatingFollow) {
      return false;
    }
    final bool follow = !current.isFollowing;
    state = AsyncData(
      current.copyWith(isUpdatingFollow: true, followUpdateFailed: false),
    );
    try {
      if (follow) {
        await _cancellation.run(
          () => repository.follow(
            session: session,
            teamId: teamId,
            rootPostId: rootPostId,
          ),
        );
      } else {
        await _cancellation.run(
          () => repository.unfollow(
            session: session,
            teamId: teamId,
            rootPostId: rootPostId,
          ),
        );
        try {
          await _cancellation.run(
            () => ref
                .read(_postponedProvider)
                .remove(
                  session: session,
                  references: <PostponedReference>[
                    PostponedReference(
                      postId: rootPostId,
                      kind: PostponedReferenceKind.thread,
                      addedAt: DateTime.now().toUtc(),
                    ),
                  ],
                ),
          );
        } on Object {
          final ThreadViewState? latest = state.value;
          if (latest != null) {
            state = AsyncData(
              latest.copyWith(
                isFollowing: false,
                isUpdatingFollow: false,
                followUpdateFailed: true,
              ),
            );
          }
          return true;
        }
      }
      final ThreadViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            isFollowing: follow,
            isUpdatingFollow: false,
            followUpdateFailed: false,
          ),
        );
      }
      return true;
    } on Object {
      final ThreadViewState? latest = state.value;
      if (!_cancellation.isCancelled && latest != null) {
        state = AsyncData(
          latest.copyWith(isUpdatingFollow: false, followUpdateFailed: true),
        );
      }
      return false;
    }
  }

  Future<bool> toggleReaction({
    required String postId,
    required String emojiName,
  }) async {
    final AuthSession? session = _session;
    final ThreadViewState? current = state.value;
    final String requestKey = '$postId\u0000$emojiName';
    if (session == null ||
        current == null ||
        !_reactionRequests.add(requestKey)) {
      return false;
    }
    final ChannelPost? original = _findPost(current.thread, postId);
    if (original == null) {
      _reactionRequests.remove(requestKey);
      return false;
    }
    final bool remove = original.reactions.any(
      (PostReaction reaction) =>
          reaction.emojiName == emojiName && reaction.reactedByCurrentUser,
    );
    _replacePost(toggleCurrentUserReaction(original, emojiName));
    try {
      if (remove) {
        await _cancellation.run(
          () => ref
              .read(_postRepositoryProvider)
              .removeReaction(
                session: session,
                postId: postId,
                emojiName: emojiName,
              ),
        );
      } else {
        await _cancellation.run(
          () => ref
              .read(_postRepositoryProvider)
              .addReaction(
                session: session,
                postId: postId,
                emojiName: emojiName,
              ),
        );
      }
      return true;
    } on Object {
      if (!_cancellation.isCancelled) {
        final ChannelPost? latest = state.value == null
            ? null
            : _findPost(state.value!.thread, postId);
        if (latest != null) {
          _replacePost(latest.withReactions(original.reactions));
        }
      }
      return false;
    } finally {
      _reactionRequests.remove(requestKey);
    }
  }

  static ChannelPost? _findPost(MessageThread thread, String postId) {
    if (thread.root?.id == postId) return thread.root;
    for (final ChannelPost reply in thread.replies) {
      if (reply.id == postId) return reply;
    }
    return null;
  }

  void _replacePost(ChannelPost replacement) {
    final ThreadViewState? current = state.value;
    if (current == null) return;
    final MessageThread thread = current.thread;
    state = AsyncData(
      current.copyWith(
        thread: MessageThread(
          rootPostId: thread.rootPostId,
          root: thread.root?.id == replacement.id ? replacement : thread.root,
          replies: List<ChannelPost>.unmodifiable(
            thread.replies.map(
              (ChannelPost post) =>
                  post.id == replacement.id ? replacement : post,
            ),
          ),
          isComplete: thread.isComplete,
          loadedAt: thread.loadedAt,
        ),
      ),
    );
  }

  static MessageThread _withSentReply(MessageThread thread, ChannelPost sent) {
    final bool wasKnown = thread.replies.any(
      (ChannelPost reply) => reply.id == sent.id,
    );
    final Map<String, ChannelPost> replies = <String, ChannelPost>{
      for (final ChannelPost reply in thread.replies) reply.id: reply,
      sent.id: sent,
    };
    final List<ChannelPost> ordered = replies.values.toList(growable: false)
      ..sort(compareMessagesBySentAt);
    final ChannelPost? root = thread.root;
    final int observedCount = ordered.length;
    final int incrementedCount = (root?.replyCount ?? 0) + (wasKnown ? 0 : 1);
    return MessageThread(
      rootPostId: thread.rootPostId,
      root: root?.withThreadSummary(
        replyCount: incrementedCount > observedCount
            ? incrementedCount
            : observedCount,
        lastReplyAt: latestDateTime(root.lastReplyAt, sent.sentAt),
      ),
      replies: List<ChannelPost>.unmodifiable(ordered),
      isComplete: thread.isComplete,
      loadedAt: thread.loadedAt,
    );
  }
}
