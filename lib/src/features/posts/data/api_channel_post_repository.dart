import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/utils/date_time_utils.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final class ApiChannelPostRepository implements ChannelPostRepository {
  const ApiChannelPostRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, MattermostUserDto> messageMapper,
  }) : _api = api,
       _messageMapper = messageMapper;

  static const int pageSize = 60;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, MattermostUserDto> _messageMapper;

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async {
    final MattermostPostListDto response = await _api.getPostsForChannel(
      channelId: channelId,
      perPage: pageSize,
    );
    return _mapPage(api: _api, session: session, response: response);
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
    return _mapPage(api: _api, session: session, response: response);
  }

  Future<ChannelPostPage> _mapPage({
    required MattermostApi api,
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
    final List<MattermostUserDto> users = userIds.isEmpty
        ? const <MattermostUserDto>[]
        : await api.getUsersByIds(userIds.toList(growable: false));
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
