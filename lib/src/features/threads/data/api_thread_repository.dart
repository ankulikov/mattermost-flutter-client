import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final class ApiThreadRepository implements ThreadRepository {
  const ApiThreadRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, MattermostUserDto> messageMapper,
  }) : _api = api,
       _messageMapper = messageMapper;

  static const int pageSize = 60;
  static const int maxPagesPerLoad = 20;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, MattermostUserDto> _messageMapper;

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async {
    final Map<String, MattermostPostDto> posts = <String, MattermostPostDto>{};
    String? fromPost;
    int? fromCreateAt;
    var hasNext = true;
    var page = 0;
    while (hasNext && page < maxPagesPerLoad) {
      final MattermostPostListDto response = await _api.getPostThread(
        rootPostId: rootPostId,
        perPage: pageSize,
        fromPost: fromPost,
        fromCreateAt: fromCreateAt,
        direction: PostThreadDirection.up,
      );
      posts.addAll(response.posts);
      hasNext = response.hasNext;
      if (!hasNext || response.order.isEmpty) break;
      final String lastId = response.order.last;
      final MattermostPostDto? last = response.posts[lastId];
      if (last == null || lastId == fromPost) break;
      fromPost = lastId;
      fromCreateAt = last.createAt;
      page += 1;
    }
    final Set<String> userIds = posts.values
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final List<MattermostUserDto> users = userIds.isEmpty
        ? const <MattermostUserDto>[]
        : await _api.getUsersByIds(userIds.toList(growable: false));
    final List<ChannelPost> mapped = _messageMapper.map(
      posts: posts.values,
      users: users,
      currentUserId: session.userId,
      includeDeleted: true,
    );
    final ChannelPost? root = mapped
        .where((ChannelPost post) => post.id == rootPostId)
        .firstOrNull;
    final List<ChannelPost> replies =
        mapped
            .where((ChannelPost post) => post.rootId == rootPostId)
            .toList(growable: false)
          ..sort(compareMessagesBySentAt);
    return MessageThread(
      rootPostId: rootPostId,
      root: root,
      replies: List<ChannelPost>.unmodifiable(replies),
      isComplete: !hasNext,
    );
  }
}
