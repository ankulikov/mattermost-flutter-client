import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final class ApiThreadRepository implements ThreadRepository {
  ApiThreadRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required UserRepository users,
    DateTime Function()? now,
  }) : _api = api,
       _messageMapper = messageMapper,
       _users = users,
       _now = now ?? DateTime.now;

  static const int pageSize = 60;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final UserRepository _users;
  final DateTime Function() _now;

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async {
    final DateTime loadedAt = _now();
    final Map<String, MattermostPostDto> posts = <String, MattermostPostDto>{};
    String? fromPost;
    int? fromCreateAt;
    final Set<String> visitedCursors = <String>{};
    var hasNext = true;
    while (hasNext) {
      final MattermostPostListDto response = await _api.getPostThread(
        rootPostId: rootPostId,
        perPage: pageSize,
        fromPost: fromPost,
        fromCreateAt: fromCreateAt,
        direction: PostThreadDirection.up,
      );
      posts.addAll(response.posts);
      hasNext = response.hasNext;
      if (!hasNext) break;
      if (response.order.isEmpty) {
        throw const FormatException(
          'Thread response has_next without a pagination cursor',
        );
      }
      final String nextId = response.nextPostId.isNotEmpty
          ? response.nextPostId
          : response.order.last;
      final MattermostPostDto? next = response.posts[nextId];
      if (next == null || !visitedCursors.add(nextId)) {
        throw const FormatException('Thread pagination cursor did not advance');
      }
      fromPost = nextId;
      fromCreateAt = next.createAt;
    }
    final Set<String> userIds = posts.values
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final List<UserSummary> users = userIds.isEmpty
        ? const <UserSummary>[]
        : await _users.getUsers(userIds.toList(growable: false));
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
      loadedAt: loadedAt,
    );
  }

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) => _api.updateThreadRead(
    userId: session.userId,
    teamId: teamId,
    threadId: rootPostId,
    timestamp: timestamp.millisecondsSinceEpoch,
  );
}
