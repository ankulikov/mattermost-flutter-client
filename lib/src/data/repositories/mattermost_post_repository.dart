import 'dart:convert';

import 'package:mattermost_flutter/src/core/utils/date_time_utils.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostPostRepository extends PostRepository {
  const MattermostPostRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required UserRepository users,
    SessionRealtimeService? realtime,
  }) : _api = api,
       _messageMapper = messageMapper,
       _users = users,
       _realtime = realtime;

  static const int pageSize = 60;
  static const int aroundPageSize = pageSize ~/ 2;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final UserRepository _users;
  final SessionRealtimeService? _realtime;

  @override
  Stream<PostRealtimeEvent> watchRealtime({
    required AuthSession session,
    String channelId = '',
    String rootPostId = '',
  }) {
    final SessionRealtimeService? realtime = _realtime;
    if (realtime == null || (channelId.isEmpty && rootPostId.isEmpty)) {
      return const Stream<PostRealtimeEvent>.empty();
    }
    return realtime
        .watch(
          session: session,
          subscription: SessionRealtimeSubscription(
            eventNames: MattermostRealtimeEventGroups.posts,
            acceptsChannel: channelId.isEmpty
                ? null
                : (String candidate) => candidate == channelId,
          ),
        )
        .asyncMap((SessionRealtimeSignal signal) async {
          switch (signal) {
            case SessionRealtimeRecoveryRequired():
              return const PostRealtimeRecoveryRequired();
            case SessionRealtimeConnectionChanged():
              return null;
            case SessionRealtimeEventReceived(:final event):
              if (channelId.isNotEmpty &&
                  event.channelId.isNotEmpty &&
                  event.channelId != channelId) {
                return null;
              }
              final MattermostPostDto? raw = _postFromEvent(event.data);
              if (raw == null || raw.id.isEmpty) {
                return const PostRealtimeRecoveryRequired();
              }
              if ((channelId.isNotEmpty && raw.channelId != channelId) ||
                  (rootPostId.isNotEmpty &&
                      raw.id != rootPostId &&
                      raw.rootId != rootPostId)) {
                return null;
              }
              try {
                final ChannelPost post = await _mapRealtimePost(session, raw);
                return event.name == 'post_deleted' || post.isDeleted
                    ? PostRealtimeDeleted(post)
                    : PostRealtimeUpserted(post);
              } on Object {
                // A failed author/projection lookup cannot safely be ignored:
                // ask the active view to reconcile from REST instead.
                return const PostRealtimeRecoveryRequired();
              }
          }
        })
        .where((PostRealtimeEvent? event) => event != null)
        .cast<PostRealtimeEvent>();
  }

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async {
    final MattermostPostListDto response = await _api.getPostsForChannel(
      channelId: channelId,
      perPage: pageSize,
    );
    return _mapPage(session: session, response: response);
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async {
    final MattermostPostListDto response = await _api.getPostsBefore(
      channelId: channelId,
      postId: beforePostId,
      perPage: pageSize,
    );
    return _mapPage(session: session, response: response);
  }

  @override
  Future<PostNavigationTarget> resolveNavigationTarget({
    required AuthSession session,
    required String postId,
  }) async {
    final MattermostPostDto post = await _api.getPost(postId);
    final MattermostChannelDto channel = await _api.getChannel(post.channelId);
    final bool isReply = post.rootId.isNotEmpty;
    final String channelPostId = isReply ? post.rootId : post.id;
    return PostNavigationTarget(
      linkedPostId: post.id,
      channelPostId: channelPostId,
      channel: mapChannel(channel),
      threadRootPostId: isReply
          ? post.rootId
          : post.replyCount > 0
          ? post.id
          : null,
      threadHighlightedPostId: isReply ? post.id : null,
    );
  }

  @override
  Future<ChannelPostPage> loadAround({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async {
    final (
      MattermostPostListDto after,
      MattermostPostDto post,
      MattermostPostListDto before,
    ) = await (
      _api.getPostsAfter(
        channelId: channelId,
        postId: postId,
        perPage: aroundPageSize,
      ),
      _api.getPost(postId),
      _api.getPostsBefore(
        channelId: channelId,
        postId: postId,
        perPage: aroundPageSize,
      ),
    ).wait;
    final MattermostPostListDto response = MattermostPostListDto(
      order: <String>[...after.order, post.id, ...before.order],
      posts: <String, MattermostPostDto>{
        ...before.posts,
        post.id: post,
        ...after.posts,
      },
      nextPostId: after.nextPostId,
      previousPostId: before.previousPostId,
      hasNext: false,
    );
    return _mapPage(
      session: session,
      response: response,
      beforePostId: before.order.lastOrNull,
      afterPostId: after.order.firstOrNull ?? post.id,
      hasOlder: before.previousPostId.isNotEmpty,
      hasNewer: after.nextPostId.isNotEmpty,
    );
  }

  @override
  Future<ChannelPostPage> loadNewer({
    required AuthSession session,
    required String channelId,
    required String afterPostId,
  }) async {
    final MattermostPostListDto response = await _api.getPostsAfter(
      channelId: channelId,
      postId: afterPostId,
      perPage: pageSize,
    );
    return _mapPage(
      session: session,
      response: response,
      afterPostId: response.order.firstOrNull,
      hasNewer: response.nextPostId.isNotEmpty,
    );
  }

  @override
  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) => sendPost(
    session: session,
    channelId: channelId,
    message: message,
    pendingPostId: pendingPostId,
    rootPostId: rootPostId,
  );

  @override
  Future<ChannelPost> sendPost({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
    List<String> fileIds = const <String>[],
  }) async {
    final MattermostPostDto post = await _api.createPost(
      MattermostCreatePostRequestDto(
        channelId: channelId,
        message: message,
        pendingPostId: pendingPostId,
        rootId: rootPostId,
        fileIds: fileIds,
      ),
    );
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: <MattermostPostDto>[post],
      users: <UserSummary>[
        UserSummary(
          id: session.userId,
          username: session.username,
          firstName: '',
          lastName: '',
          nickname: '',
          position: '',
          email: '',
        ),
      ],
      currentUserId: session.userId,
      includeDeleted: true,
    );
    if (mapped case <ChannelPost>[final ChannelPost result]) return result;
    throw const FormatException('Create post response could not be mapped');
  }

  @override
  Future<void> deletePost({
    required AuthSession session,
    required String postId,
  }) => _api.deletePost(postId);

  @override
  Future<ChannelPost> updateMessage({
    required AuthSession session,
    required String postId,
    required String message,
  }) async {
    final MattermostPostDto post = await _api.updatePostMessage(
      postId: postId,
      message: message,
    );
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: <MattermostPostDto>[post],
      users: <UserSummary>[
        UserSummary(
          id: session.userId,
          username: session.username,
          firstName: '',
          lastName: '',
          nickname: '',
          position: '',
          email: '',
        ),
      ],
      currentUserId: session.userId,
      includeDeleted: true,
    );
    if (mapped case <ChannelPost>[final ChannelPost result]) return result;
    throw const FormatException('Updated post response could not be mapped');
  }

  @override
  Future<void> addReaction({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) => _api.saveReaction(
    userId: session.userId,
    postId: postId,
    emojiName: emojiName,
  );

  @override
  Future<void> removeReaction({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) => _api.deleteReaction(
    userId: session.userId,
    postId: postId,
    emojiName: emojiName,
  );

  Future<ChannelPost> _mapRealtimePost(
    AuthSession session,
    MattermostPostDto raw,
  ) async {
    final List<UserSummary> authors = raw.userId.isEmpty
        ? const <UserSummary>[]
        : await _users.getUsers(<String>[raw.userId]);
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: <MattermostPostDto>[raw],
      users: authors,
      currentUserId: session.userId,
      includeDeleted: true,
    );
    if (mapped case <ChannelPost>[final ChannelPost post]) return post;
    throw const FormatException('Realtime post could not be mapped');
  }

  static MattermostPostDto? _postFromEvent(Map<String, Object?> data) {
    final Object? encoded = data['post'];
    final Object? decoded;
    try {
      decoded = encoded is String ? jsonDecode(encoded) : encoded;
    } on FormatException {
      return null;
    }
    if (decoded is! Map<Object?, Object?>) return null;
    return MattermostPostDto.fromJson(
      decoded.map(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key is String ? key : key.toString(),
          value,
        ),
      ),
    );
  }

  Future<ChannelPostPage> _mapPage({
    required AuthSession session,
    required MattermostPostListDto response,
    String? beforePostId,
    String? afterPostId,
    bool? hasOlder,
    bool? hasNewer,
  }) async {
    final List<MattermostPostDto> orderedPosts = response.order
        .map((String id) => response.posts[id])
        .whereType<MattermostPostDto>()
        .toList(growable: false);
    final Set<String> userIds = orderedPosts
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final List<UserSummary> users = userIds.isEmpty
        ? const <UserSummary>[]
        : await _users.getUsers(userIds.toList(growable: false));
    final List<ChannelPost> mappedPosts = _messageMapper.map(
      posts: orderedPosts,
      users: users,
      currentUserId: session.userId,
    );
    final Map<String, ChannelReplySummary> replySummaries =
        _collectReplySummaries(mappedPosts);
    final List<ChannelPost> roots =
        mappedPosts
            .where((ChannelPost post) => !post.isReply)
            .map(
              (ChannelPost post) =>
                  _applyReplySummary(post, replySummaries[post.id]),
            )
            .toList(growable: false)
          ..sort(compareMessagesBySentAt);
    final String? resolvedBeforePostId =
        beforePostId ?? response.order.lastOrNull;
    return ChannelPostPage(
      posts: List<ChannelPost>.unmodifiable(roots),
      replySummaries: Map<String, ChannelReplySummary>.unmodifiable(
        replySummaries,
      ),
      beforePostId: resolvedBeforePostId,
      afterPostId: afterPostId,
      hasOlder:
          hasOlder ??
          (resolvedBeforePostId != null && response.previousPostId.isNotEmpty),
      hasNewer: hasNewer ?? false,
    );
  }

  static Map<String, ChannelReplySummary> _collectReplySummaries(
    List<ChannelPost> posts,
  ) {
    final Map<String, Set<String>> replyIds = <String, Set<String>>{};
    final Map<String, DateTime> lastReplyAt = <String, DateTime>{};
    for (final ChannelPost post in posts) {
      if (!post.isReply) continue;
      replyIds.putIfAbsent(post.rootId, () => <String>{}).add(post.id);
      final DateTime? currentLastReplyAt = lastReplyAt[post.rootId];
      if (currentLastReplyAt == null ||
          post.sentAt.isAfter(currentLastReplyAt)) {
        lastReplyAt[post.rootId] = post.sentAt;
      }
    }
    return <String, ChannelReplySummary>{
      for (final MapEntry<String, Set<String>> entry in replyIds.entries)
        entry.key: ChannelReplySummary(
          replyIds: Set<String>.unmodifiable(entry.value),
          lastReplyAt: lastReplyAt[entry.key],
        ),
    };
  }

  static ChannelPost _applyReplySummary(
    ChannelPost post,
    ChannelReplySummary? summary,
  ) {
    if (summary == null) return post;
    final int observedCount = summary.replyIds.length;
    return post.withThreadSummary(
      replyCount: post.replyCount > observedCount
          ? post.replyCount
          : observedCount,
      lastReplyAt: latestDateTime(post.lastReplyAt, summary.lastReplyAt),
    );
  }
}
