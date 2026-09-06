import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostThreadRepository extends ThreadRepository {
  MattermostThreadRepository({
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

  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async {
    final MattermostUserThreadsDto response = await _api.getUserThreads(
      userId: session.userId,
      teamId: teamId,
      perPage: pageSize,
      before: before,
      extended: true,
    );
    final List<MattermostUserThreadDto> rawThreads = response.threads
        .where((thread) => thread.deleteAt == 0 && thread.post != null)
        .toList(growable: false);
    final Map<String, UserSummary> usersById = <String, UserSummary>{
      for (final MattermostUserThreadDto thread in rawThreads)
        for (final MattermostUserDto user in thread.participants)
          user.id: mapUserSummary(user),
    };
    final Set<String> missingAuthorIds = rawThreads
        .map((thread) => thread.post!.userId)
        .where((String id) => id.isNotEmpty && !usersById.containsKey(id))
        .toSet();
    if (missingAuthorIds.isNotEmpty) {
      try {
        final List<UserSummary> authors = await _users.getUsers(
          missingAuthorIds.toList(growable: false),
        );
        usersById.addEntries(authors.map((user) => MapEntry(user.id, user)));
      } on Object {
        // Thread content remains useful with an id as the author fallback.
      }
    }
    final List<FollowedThread> items = rawThreads
        .map((raw) {
          final MattermostPostDto post = raw.post!;
          final ChannelPost root = _messageMapper
              .map(
                posts: <MattermostPostDto>[post],
                users: usersById.values,
                currentUserId: session.userId,
                includeDeleted: true,
              )
              .single;
          return FollowedThread(
            root: root.withThreadSummary(
              replyCount: raw.replyCount,
              lastReplyAt: _dateOrNull(raw.lastReplyAt),
            ),
            replyCount: raw.replyCount,
            lastReplyAt: _dateOrEpoch(raw.lastReplyAt),
            lastViewedAt: _dateOrEpoch(raw.lastViewedAt),
            unreadReplies: raw.unreadReplies,
            unreadMentions: raw.unreadMentions,
            participants: List<PostAuthor>.unmodifiable(
              raw.participants.map((MattermostUserDto rawUser) {
                final UserSummary user = mapUserSummary(rawUser);
                return PostAuthor(
                  id: user.id,
                  displayName: user.fullName,
                  profileImageUpdatedAt: user.profileImageUpdatedAt,
                );
              }),
            ),
          );
        })
        .toList(growable: false);
    return FollowedThreadsPage(
      items: List<FollowedThread>.unmodifiable(items),
      total: response.total,
      totalUnreadThreads: response.totalUnreadThreads,
      totalUnreadMentions: response.totalUnreadMentions,
    );
  }

  @override
  Future<bool> isFollowing({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) async =>
      await _api.getUserThread(
        userId: session.userId,
        teamId: teamId,
        threadId: rootPostId,
      ) !=
      null;

  @override
  Future<void> follow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) => _api.followThread(
    userId: session.userId,
    teamId: teamId,
    threadId: rootPostId,
  );

  @override
  Future<void> unfollow({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
  }) => _api.unfollowThread(
    userId: session.userId,
    teamId: teamId,
    threadId: rootPostId,
  );

  static DateTime _dateOrEpoch(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds);

  static DateTime? _dateOrNull(int milliseconds) =>
      milliseconds == 0 ? null : _dateOrEpoch(milliseconds);
}
