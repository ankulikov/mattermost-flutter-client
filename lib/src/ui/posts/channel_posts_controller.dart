import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/core/utils/date_time_utils.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/policies/post_collection.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';

final class ChannelPostsViewState {
  const ChannelPostsViewState({
    required this.posts,
    required this.hasOlder,
    this.hasNewer = false,
    this.replySummaries = const <String, ChannelReplySummary>{},
    this.beforePostId,
    this.afterPostId,
    this.olderLoadStatus = const OperationStatus.idle(),
    this.newerLoadStatus = const OperationStatus.idle(),
    this.focusStatus = const OperationStatus.idle(),
    this.focusPostId,
  });

  final List<ChannelPost> posts;
  final bool hasOlder;
  final bool hasNewer;
  final Map<String, ChannelReplySummary> replySummaries;
  final String? beforePostId;
  final String? afterPostId;
  final OperationStatus olderLoadStatus;
  final OperationStatus newerLoadStatus;
  final OperationStatus focusStatus;
  final String? focusPostId;

  ChannelPostsViewState copyWith({
    List<ChannelPost>? posts,
    bool? hasOlder,
    bool? hasNewer,
    Map<String, ChannelReplySummary>? replySummaries,
    String? beforePostId,
    String? afterPostId,
    OperationStatus? olderLoadStatus,
    OperationStatus? newerLoadStatus,
    OperationStatus? focusStatus,
    String? focusPostId,
  }) => ChannelPostsViewState(
    posts: posts ?? this.posts,
    hasOlder: hasOlder ?? this.hasOlder,
    hasNewer: hasNewer ?? this.hasNewer,
    replySummaries: replySummaries ?? this.replySummaries,
    beforePostId: beforePostId ?? this.beforePostId,
    afterPostId: afterPostId ?? this.afterPostId,
    olderLoadStatus: olderLoadStatus ?? this.olderLoadStatus,
    newerLoadStatus: newerLoadStatus ?? this.newerLoadStatus,
    focusStatus: focusStatus ?? this.focusStatus,
    focusPostId: focusPostId ?? this.focusPostId,
  );
}

final class ChannelPostsController
    extends AsyncNotifier<ChannelPostsViewState> {
  ChannelPostsController(
    this.channelId,
    this._sessionProvider,
    this._repositoryProvider,
  );

  static const int _maxBufferedRealtimeEvents = 1000;
  final String channelId;
  final Provider<AuthSession?> _sessionProvider;
  final Provider<PostRepository> _repositoryProvider;
  late RequestCancellation _cancellation;
  AuthSession? _session;
  PostRepository? _repository;
  bool _sendRunning = false;
  int _focusRequest = 0;
  String? _requestedFocusPostId;
  final Set<String> _reactionRequests = <String>{};
  final Set<String> _deleteRequests = <String>{};
  final Set<String> _editRequests = <String>{};
  StreamSubscription<PostRealtimeEvent>? _realtimeSubscription;
  final List<_VersionedPostRealtimeEvent> _realtimeEvents =
      <_VersionedPostRealtimeEvent>[];
  final Map<int, int> _realtimeBaselines = <int, int>{};
  int _realtimeRevision = 0;
  int _realtimeRequest = 0;
  int _realtimeGeneration = 0;
  bool _recoveryPending = false;
  bool _recoveryRunning = false;

  @override
  Future<ChannelPostsViewState> build() async {
    final RequestCancellation cancellation = RequestCancellation();
    _cancellation = cancellation;
    ref.onDispose(cancellation.cancel);
    _session = null;
    _repository = null;
    final AuthSession? session = ref.watch(_sessionProvider);
    if (session == null) {
      _stopRealtime();
      return const ChannelPostsViewState(
        posts: <ChannelPost>[],
        hasOlder: false,
      );
    }
    final PostRepository repository = ref.watch(_repositoryProvider);
    _session = session;
    _repository = repository;
    final int generation = _startRealtime(session, repository);
    final _RealtimeBaseline baseline = _beginRealtimeReconciliation();
    try {
      final ChannelPostsViewState loaded = await cancellation.run(
        () => _loadLatest(session, repository),
      );
      return _applyRealtimeEvents(loaded, _eventsAfter(baseline.revision));
    } finally {
      _finishRealtimeReconciliation(baseline.token);
      _scheduleRealtimeDrain(generation);
    }
  }

  Future<void> retry() async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    if (session == null || repository == null) return;
    final RequestCancellation cancellation = _cancellation;
    state = const AsyncLoading<ChannelPostsViewState>();
    final _RealtimeBaseline baseline = _beginRealtimeReconciliation();
    try {
      final ChannelPostsViewState loaded = await cancellation.run(
        () => _loadLatest(session, repository),
      );
      state = AsyncData(
        _applyRealtimeEvents(loaded, _eventsAfter(baseline.revision)),
      );
    } on Object catch (error, stackTrace) {
      if (cancellation.isCancelled) return;
      state = AsyncError<ChannelPostsViewState>(error, stackTrace);
    } finally {
      _finishRealtimeReconciliation(baseline.token);
      _scheduleRealtimeDrain(_realtimeGeneration);
    }
  }

  Future<void> loadOlder() async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    final ChannelPostsViewState? current = state.value;
    final String? beforePostId = current?.beforePostId;
    if (session == null ||
        repository == null ||
        current == null ||
        current.olderLoadStatus is OperationInProgress ||
        beforePostId == null ||
        !current.hasOlder) {
      return;
    }
    final RequestCancellation cancellation = _cancellation;
    state = AsyncData(
      current.copyWith(olderLoadStatus: const OperationStatus.inProgress()),
    );
    final _RealtimeBaseline baseline = _beginRealtimeReconciliation();
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
          mergeReplySummaries(latest.replySummaries, page.replySummaries);
      state = AsyncData(
        _applyRealtimeEvents(
          latest.copyWith(
            posts: applyReplySummaries(
              mergePosts(latest.posts, page.posts),
              replySummaries,
            ),
            hasOlder: page.hasOlder,
            replySummaries: replySummaries,
            beforePostId: page.beforePostId,
            olderLoadStatus: const OperationStatus.idle(),
          ),
          _eventsAfter(baseline.revision),
        ),
      );
    } on Object catch (error) {
      if (cancellation.isCancelled) return;
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(olderLoadStatus: OperationStatus.failed(error)),
        );
      }
    } finally {
      _finishRealtimeReconciliation(baseline.token);
      if (!cancellation.isCancelled) {
        final ChannelPostsViewState? latest = state.value;
        if (latest != null && latest.olderLoadStatus is OperationInProgress) {
          state = AsyncData(
            latest.copyWith(olderLoadStatus: const OperationStatus.idle()),
          );
        }
      }
    }
  }

  Future<void> loadNewer() async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    final ChannelPostsViewState? current = state.value;
    final String? afterPostId = current?.afterPostId;
    if (session == null ||
        repository == null ||
        current == null ||
        current.newerLoadStatus is OperationInProgress ||
        afterPostId == null ||
        !current.hasNewer) {
      return;
    }
    final RequestCancellation cancellation = _cancellation;
    state = AsyncData(
      current.copyWith(newerLoadStatus: const OperationStatus.inProgress()),
    );
    final _RealtimeBaseline baseline = _beginRealtimeReconciliation();
    try {
      final ChannelPostPage page = await cancellation.run(
        () => repository.loadNewer(
          session: session,
          channelId: channelId,
          afterPostId: afterPostId,
        ),
      );
      final ChannelPostsViewState? latest = state.value;
      if (latest == null) return;
      final Map<String, ChannelReplySummary> replySummaries =
          mergeReplySummaries(latest.replySummaries, page.replySummaries);
      state = AsyncData(
        _applyRealtimeEvents(
          latest.copyWith(
            posts: applyReplySummaries(
              mergePosts(latest.posts, page.posts),
              replySummaries,
            ),
            hasNewer: page.hasNewer,
            replySummaries: replySummaries,
            afterPostId: page.afterPostId ?? afterPostId,
            newerLoadStatus: const OperationStatus.idle(),
          ),
          _eventsAfter(baseline.revision),
        ),
      );
    } on Object catch (error) {
      if (cancellation.isCancelled) return;
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(newerLoadStatus: OperationStatus.failed(error)),
        );
      }
    } finally {
      _finishRealtimeReconciliation(baseline.token);
      if (!cancellation.isCancelled) {
        final ChannelPostsViewState? latest = state.value;
        if (latest != null && latest.newerLoadStatus is OperationInProgress) {
          state = AsyncData(
            latest.copyWith(newerLoadStatus: const OperationStatus.idle()),
          );
        }
      }
    }
  }

  Future<void> focusOn(String postId) async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    final ChannelPostsViewState current =
        state.value ??
        const ChannelPostsViewState(posts: <ChannelPost>[], hasOlder: false);
    if (session == null || repository == null) return;
    if (current.focusPostId == postId &&
        current.focusStatus is! OperationFailed) {
      return;
    }
    _requestedFocusPostId = postId;
    final int request = ++_focusRequest;
    final RequestCancellation cancellation = _cancellation;
    state = AsyncData(
      current.copyWith(focusStatus: const OperationStatus.inProgress()),
    );
    final _RealtimeBaseline baseline = _beginRealtimeReconciliation();
    try {
      final ChannelPostPage page = await cancellation.run(
        () => repository.loadAround(
          session: session,
          channelId: channelId,
          postId: postId,
        ),
      );
      if (request != _focusRequest || cancellation.isCancelled) return;
      state = AsyncData(
        _applyRealtimeEvents(
          ChannelPostsViewState(
            posts: page.posts,
            hasOlder: page.hasOlder,
            hasNewer: page.hasNewer,
            replySummaries: page.replySummaries,
            beforePostId: page.beforePostId,
            afterPostId: page.afterPostId,
            focusPostId: postId,
          ),
          _eventsAfter(baseline.revision),
        ),
      );
    } on Object catch (error) {
      if (request != _focusRequest || cancellation.isCancelled) return;
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(focusStatus: OperationStatus.failed(error)),
        );
      }
    } finally {
      _finishRealtimeReconciliation(baseline.token);
    }
  }

  Future<void> retryFocus() async {
    final String? postId = _requestedFocusPostId;
    if (postId == null) return;
    await focusOn(postId);
  }

  Future<ChannelPost> sendText({
    required String message,
    required String pendingPostId,
    List<String> fileIds = const <String>[],
  }) async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    if (_sendRunning) {
      throw StateError('A channel message is already being sent');
    }
    if (session == null || repository == null || state.value == null) {
      throw StateError('Channel messages are not ready');
    }
    _sendRunning = true;
    try {
      final ChannelPost sent = await _cancellation.run(
        () => repository.sendPost(
          session: session,
          channelId: channelId,
          message: message,
          pendingPostId: pendingPostId,
          fileIds: fileIds,
        ),
      );
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(posts: mergePosts(latest.posts, <ChannelPost>[sent])),
        );
      }
      return sent;
    } finally {
      _sendRunning = false;
    }
  }

  Future<ChannelPost> editMessage({
    required String postId,
    required String message,
  }) async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    if (session == null || repository == null || state.value == null) {
      throw StateError('Channel messages are not ready');
    }
    if (!_editRequests.add(postId)) {
      throw StateError('This message is already being edited');
    }
    try {
      final ChannelPost updated = await _cancellation.run(
        () => repository.updateMessage(
          session: session,
          postId: postId,
          message: message,
        ),
      );
      replacePost(updated);
      return updated;
    } finally {
      _editRequests.remove(postId);
    }
  }

  Future<bool> toggleReaction({
    required String postId,
    required String emojiName,
  }) async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    final ChannelPostsViewState? current = state.value;
    final String requestKey = '$postId\u0000$emojiName';
    if (session == null ||
        repository == null ||
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
    replacePost(
      toggleCurrentUserReaction(
        original,
        emojiName,
        currentUserId: session.userId,
      ),
    );
    try {
      if (remove) {
        await _cancellation.run(
          () => repository.removeReaction(
            session: session,
            postId: postId,
            emojiName: emojiName,
          ),
        );
      } else {
        await _cancellation.run(
          () => repository.addReaction(
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
          replacePost(latest.withReactions(original.reactions));
        }
      }
      return false;
    } finally {
      _reactionRequests.remove(requestKey);
    }
  }

  /// Removes a successfully deleted root post from the open channel snapshot.
  Future<bool> deletePost(String postId) async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    final ChannelPostsViewState? current = state.value;
    if (session == null ||
        repository == null ||
        current == null ||
        !_deleteRequests.add(postId) ||
        !current.posts.any((ChannelPost post) => post.id == postId)) {
      return false;
    }
    try {
      await _cancellation.run(
        () => repository.deletePost(session: session, postId: postId),
      );
      if (_cancellation.isCancelled) return false;
      final ChannelPostsViewState? latest = state.value;
      if (latest != null) {
        _removePostFromSnapshot(latest, postId: postId);
      }
      return true;
    } on Object {
      return false;
    } finally {
      _deleteRequests.remove(postId);
    }
  }

  /// Applies a deletion already acknowledged by another open view, such as a
  /// side thread, without issuing a duplicate REST request.
  void removePostLocally(ChannelPost post) {
    final ChannelPostsViewState? current = state.value;
    if (current == null) return;
    _removePostFromSnapshot(current, postId: post.id, reply: post);
  }

  void _removePostFromSnapshot(
    ChannelPostsViewState current, {
    required String postId,
    ChannelPost? reply,
  }) {
    state = AsyncData(_withoutPost(current, postId: postId, reply: reply));
  }

  static ChannelPostsViewState _withoutPost(
    ChannelPostsViewState current, {
    required String postId,
    ChannelPost? reply,
  }) {
    String rootId = reply?.rootId ?? '';
    if (rootId.isEmpty) {
      for (final MapEntry<String, ChannelReplySummary> entry
          in current.replySummaries.entries) {
        if (entry.value.replyIds.contains(postId)) {
          rootId = entry.key;
          break;
        }
      }
    }
    if (rootId.isEmpty) {
      final ChannelPost? existing = current.posts
          .where((ChannelPost post) => post.id == postId)
          .firstOrNull;
      if (reply != null &&
          existing != null &&
          existing.revisionAt.isAfter(reply.revisionAt)) {
        return current;
      }
      return current.copyWith(
        posts: List<ChannelPost>.unmodifiable(
          current.posts.where((ChannelPost post) => post.id != postId),
        ),
      );
    }
    final ChannelReplySummary? summary = current.replySummaries[rootId];
    final bool wasKnown = summary?.replyIds.contains(postId) == true;
    final Map<String, ChannelReplySummary> summaries =
        <String, ChannelReplySummary>{...current.replySummaries};
    if (summary != null && wasKnown) {
      summaries[rootId] = ChannelReplySummary(
        replyIds: Set<String>.unmodifiable(
          summary.replyIds.where((String id) => id != postId),
        ),
        lastReplyAt: summary.lastReplyAt,
      );
    }
    return current.copyWith(
      posts: List<ChannelPost>.unmodifiable(
        current.posts.map((ChannelPost post) {
          if (post.id != rootId || !wasKnown) return post;
          return post.withThreadSummary(
            replyCount: post.replyCount > 0 ? post.replyCount - 1 : 0,
            lastReplyAt: post.lastReplyAt,
          );
        }),
      ),
      replySummaries: Map<String, ChannelReplySummary>.unmodifiable(summaries),
    );
  }

  /// Replaces a post using the same canonical collection policy as updates.
  void replacePost(ChannelPost replacement) {
    final ChannelPostsViewState? current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        posts: mergePosts(current.posts, <ChannelPost>[replacement]),
      ),
    );
  }

  void recordSentReply(ChannelPost reply) {
    final ChannelPostsViewState? current = state.value;
    if (current == null || reply.rootId.isEmpty) return;
    state = AsyncData(_withRecordedReply(current, reply));
  }

  static ChannelPostsViewState _withRecordedReply(
    ChannelPostsViewState current,
    ChannelPost reply,
  ) {
    final ChannelReplySummary? previous = current.replySummaries[reply.rootId];
    final bool wasKnown = previous?.replyIds.contains(reply.id) == true;
    final ChannelReplySummary updatedSummary = ChannelReplySummary(
      replyIds: Set<String>.unmodifiable(<String>{
        ...?previous?.replyIds,
        reply.id,
      }),
      lastReplyAt: latestDateTime(previous?.lastReplyAt, reply.sentAt),
    );
    final Map<String, ChannelReplySummary> summaries =
        Map<String, ChannelReplySummary>.unmodifiable(
          <String, ChannelReplySummary>{
            ...current.replySummaries,
            reply.rootId: updatedSummary,
          },
        );
    return current.copyWith(
      posts: List<ChannelPost>.unmodifiable(
        current.posts.map((ChannelPost post) {
          if (post.id != reply.rootId) return post;
          final int incrementedCount = post.replyCount + (wasKnown ? 0 : 1);
          final int observedCount = updatedSummary.replyIds.length;
          return post.withThreadSummary(
            replyCount: incrementedCount > observedCount
                ? incrementedCount
                : observedCount,
            lastReplyAt: latestDateTime(post.lastReplyAt, reply.sentAt),
          );
        }),
      ),
      replySummaries: summaries,
    );
  }

  int _startRealtime(AuthSession session, PostRepository repository) {
    final int generation = ++_realtimeGeneration;
    final StreamSubscription<PostRealtimeEvent>? previous =
        _realtimeSubscription;
    if (previous != null) unawaited(previous.cancel());
    _realtimeEvents.clear();
    _realtimeBaselines.clear();
    _realtimeRevision = 0;
    _recoveryPending = false;
    _recoveryRunning = false;
    final StreamSubscription<PostRealtimeEvent> subscription = repository
        .watchRealtime(session: session, channelId: channelId)
        .listen(
          (PostRealtimeEvent event) => _onRealtimeEvent(event, generation),
          onError: (Object _, StackTrace _) =>
              _requestRealtimeRecovery(generation),
        );
    _realtimeSubscription = subscription;
    ref.onDispose(() {
      if (_realtimeGeneration == generation) _realtimeGeneration += 1;
      unawaited(subscription.cancel());
    });
    return generation;
  }

  void _stopRealtime() {
    _realtimeGeneration += 1;
    final StreamSubscription<PostRealtimeEvent>? subscription =
        _realtimeSubscription;
    _realtimeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    _realtimeEvents.clear();
    _realtimeBaselines.clear();
    _recoveryPending = false;
    _recoveryRunning = false;
  }

  void _onRealtimeEvent(PostRealtimeEvent event, int generation) {
    if (generation != _realtimeGeneration || _cancellation.isCancelled) return;
    _realtimeRevision += 1;
    var bufferOverflowed = false;
    if (_realtimeBaselines.isNotEmpty || state.value == null) {
      _realtimeEvents.add(
        _VersionedPostRealtimeEvent(_realtimeRevision, event),
      );
      if (_realtimeEvents.length > _maxBufferedRealtimeEvents) {
        _realtimeEvents.removeRange(
          0,
          _realtimeEvents.length - _maxBufferedRealtimeEvents,
        );
        _recoveryPending = true;
        bufferOverflowed = true;
      }
    }
    if (event is PostRealtimeRecoveryRequired) {
      _requestRealtimeRecovery(generation);
      return;
    }
    final ChannelPostsViewState? current = state.value;
    if (current != null) {
      state = AsyncData(_applyRealtimeEvent(current, event));
    }
    if (bufferOverflowed) _requestRealtimeRecovery(generation);
  }

  _RealtimeBaseline _beginRealtimeReconciliation() {
    final int token = ++_realtimeRequest;
    _realtimeBaselines[token] = _realtimeRevision;
    return (token: token, revision: _realtimeRevision);
  }

  List<PostRealtimeEvent> _eventsAfter(int revision) => _realtimeEvents
      .where((_VersionedPostRealtimeEvent item) => item.revision > revision)
      .map((_VersionedPostRealtimeEvent item) => item.event)
      .toList(growable: false);

  void _finishRealtimeReconciliation(int token) {
    _realtimeBaselines.remove(token);
    _pruneRealtimeEvents();
    if (_recoveryPending && _realtimeBaselines.isEmpty) {
      _requestRealtimeRecovery(_realtimeGeneration);
    }
  }

  void _pruneRealtimeEvents() {
    if (_realtimeBaselines.isEmpty) {
      if (state.value != null) _realtimeEvents.clear();
      return;
    }
    final int oldestBaseline = _realtimeBaselines.values.reduce(
      (int first, int second) => first < second ? first : second,
    );
    _realtimeEvents.removeWhere(
      (_VersionedPostRealtimeEvent item) => item.revision <= oldestBaseline,
    );
  }

  void _scheduleRealtimeDrain(int generation) {
    unawaited(
      Future<void>.delayed(Duration.zero, () {
        if (generation != _realtimeGeneration || _cancellation.isCancelled) {
          return;
        }
        final ChannelPostsViewState? current = state.value;
        if (current != null && _realtimeEvents.isNotEmpty) {
          state = AsyncData(
            _applyRealtimeEvents(
              current,
              _realtimeEvents
                  .map((_VersionedPostRealtimeEvent item) => item.event)
                  .toList(growable: false),
            ),
          );
          _pruneRealtimeEvents();
        }
        if (_recoveryPending) _requestRealtimeRecovery(generation);
      }),
    );
  }

  ChannelPostsViewState _applyRealtimeEvents(
    ChannelPostsViewState current,
    Iterable<PostRealtimeEvent> events,
  ) {
    ChannelPostsViewState result = current;
    for (final PostRealtimeEvent event in events) {
      result = _applyRealtimeEvent(result, event);
    }
    return result;
  }

  ChannelPostsViewState _applyRealtimeEvent(
    ChannelPostsViewState current,
    PostRealtimeEvent event,
  ) => switch (event) {
    PostRealtimeUpserted(:final post)
        when post.channelId == channelId && post.isReply =>
      _withRecordedReply(current, post),
    PostRealtimeUpserted(:final post) when post.channelId == channelId =>
      current.copyWith(
        posts: applyReplySummaries(
          mergePosts(current.posts, <ChannelPost>[post]),
          current.replySummaries,
        ),
      ),
    PostRealtimeDeleted(:final post) when post.channelId == channelId =>
      _withoutPost(current, postId: post.id, reply: post),
    PostRealtimeReactionChanged(
      :final postId,
      :final userId,
      :final emojiName,
      :final added,
    ) =>
      current.copyWith(
        posts: current.posts
            .map(
              (ChannelPost post) => post.id == postId
                  ? applyRealtimeReaction(
                      post,
                      emojiName: emojiName,
                      userId: userId,
                      added: added,
                      currentUserId: _session?.userId ?? '',
                    )
                  : post,
            )
            .toList(growable: false),
      ),
    _ => current,
  };

  void _requestRealtimeRecovery(int generation) {
    if (generation != _realtimeGeneration || _cancellation.isCancelled) return;
    _recoveryPending = true;
    if (_recoveryRunning ||
        _realtimeBaselines.isNotEmpty ||
        state.value == null) {
      return;
    }
    unawaited(_recoverRealtime(generation));
  }

  Future<void> _recoverRealtime(int generation) async {
    final AuthSession? session = _session;
    final PostRepository? repository = _repository;
    if (session == null || repository == null || _recoveryRunning) return;
    _recoveryRunning = true;
    try {
      while (_recoveryPending &&
          generation == _realtimeGeneration &&
          !_cancellation.isCancelled) {
        _recoveryPending = false;
        final ChannelPostsViewState? current = state.value;
        if (current == null) return;
        final _RealtimeBaseline baseline = _beginRealtimeReconciliation();
        try {
          final String? focusPostId = current.focusPostId;
          final ChannelPostPage page = await _cancellation.run(
            () => focusPostId == null
                ? repository.loadLatest(session: session, channelId: channelId)
                : repository.loadAround(
                    session: session,
                    channelId: channelId,
                    postId: focusPostId,
                  ),
          );
          if (generation != _realtimeGeneration || _cancellation.isCancelled) {
            return;
          }
          final ChannelPostsViewState recovered = ChannelPostsViewState(
            posts: page.posts,
            hasOlder: page.hasOlder,
            hasNewer: page.hasNewer,
            replySummaries: page.replySummaries,
            beforePostId: page.beforePostId,
            afterPostId: page.afterPostId,
            focusPostId: focusPostId,
          );
          state = AsyncData(
            _applyRealtimeEvents(recovered, _eventsAfter(baseline.revision)),
          );
        } on Object {
          // Keep the useful snapshot; another recovery signal or explicit
          // navigation retry can attempt the authoritative reload again.
        } finally {
          _finishRealtimeReconciliation(baseline.token);
        }
      }
    } finally {
      if (generation == _realtimeGeneration) {
        _recoveryRunning = false;
        if (_recoveryPending && !_cancellation.isCancelled) {
          _requestRealtimeRecovery(generation);
        }
      }
    }
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
}

typedef _RealtimeBaseline = ({int token, int revision});

final class _VersionedPostRealtimeEvent {
  const _VersionedPostRealtimeEvent(this.revision, this.event);

  final int revision;
  final PostRealtimeEvent event;
}
