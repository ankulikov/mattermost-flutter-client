import 'package:mattermost_flutter/src/core/utils/date_time_utils.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostPostRepository extends PostRepository {
  const MattermostPostRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required UserRepository users,
  }) : _api = api,
       _messageMapper = messageMapper,
       _users = users;

  static const int pageSize = 60;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final UserRepository _users;

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
  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) async {
    final MattermostPostDto post = await _api.createPost(
      MattermostCreatePostRequestDto(
        channelId: channelId,
        message: message,
        pendingPostId: pendingPostId,
        rootId: rootPostId,
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

  Future<ChannelPostPage> _mapPage({
    required AuthSession session,
    required MattermostPostListDto response,
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
    final String? beforePostId = response.order.lastOrNull;
    return ChannelPostPage(
      posts: List<ChannelPost>.unmodifiable(roots),
      replySummaries: Map<String, ChannelReplySummary>.unmodifiable(
        replySummaries,
      ),
      beforePostId: beforePostId,
      hasOlder: beforePostId != null && response.previousPostId.isNotEmpty,
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
