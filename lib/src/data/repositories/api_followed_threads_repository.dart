import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/followed_threads_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class ApiFollowedThreadsRepository implements FollowedThreadsRepository {
  const ApiFollowedThreadsRepository({
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
  Future<FollowedThreadsPage> loadPage({
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
        .where(
          (MattermostUserThreadDto thread) =>
              thread.deleteAt == 0 && thread.post != null,
        )
        .toList(growable: false);
    final Map<String, UserSummary> usersById = <String, UserSummary>{
      for (final MattermostUserThreadDto thread in rawThreads)
        for (final MattermostUserDto user in thread.participants)
          user.id: mapUserSummary(user),
    };
    final Set<String> missingAuthorIds = rawThreads
        .map((MattermostUserThreadDto thread) => thread.post!.userId)
        .where((String id) => id.isNotEmpty && !usersById.containsKey(id))
        .toSet();
    if (missingAuthorIds.isNotEmpty) {
      try {
        final List<UserSummary> authors = await _users.getUsers(
          missingAuthorIds.toList(growable: false),
        );
        usersById.addEntries(
          authors.map(
            (UserSummary user) => MapEntry<String, UserSummary>(user.id, user),
          ),
        );
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

  static DateTime _dateOrEpoch(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds);

  static DateTime? _dateOrNull(int milliseconds) =>
      milliseconds == 0 ? null : _dateOrEpoch(milliseconds);
}
