import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_threads_repository.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_display_name.dart';

final class ApiFollowedThreadsRepository implements FollowedThreadsRepository {
  const ApiFollowedThreadsRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, MattermostUserDto> messageMapper,
  }) : _api = api,
       _messageMapper = messageMapper;

  static const int pageSize = 60;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, MattermostUserDto> _messageMapper;

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
    final Map<String, MattermostUserDto> usersById =
        <String, MattermostUserDto>{
          for (final MattermostUserThreadDto thread in rawThreads)
            for (final MattermostUserDto user in thread.participants)
              user.id: user,
        };
    final Set<String> missingAuthorIds = rawThreads
        .map((MattermostUserThreadDto thread) => thread.post!.userId)
        .where((String id) => id.isNotEmpty && !usersById.containsKey(id))
        .toSet();
    if (missingAuthorIds.isNotEmpty) {
      try {
        final List<MattermostUserDto> authors = await _api.getUsersByIds(
          missingAuthorIds.toList(growable: false),
        );
        usersById.addEntries(
          authors.map(
            (MattermostUserDto user) =>
                MapEntry<String, MattermostUserDto>(user.id, user),
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
              raw.participants.map(
                (MattermostUserDto user) =>
                    PostAuthor(id: user.id, displayName: _displayName(user)),
              ),
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

  static String _displayName(MattermostUserDto user) => resolveUserDisplayName(
    id: user.id,
    username: user.username,
    nickname: user.nickname,
    firstName: user.firstName,
    lastName: user.lastName,
  );
}
