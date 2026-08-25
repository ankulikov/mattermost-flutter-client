import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/followed_threads_repository.dart';

final class ApiFollowedThreadsRepository implements FollowedThreadsRepository {
  ApiFollowedThreadsRepository({
    required CredentialStore credentialStore,
    MattermostApiFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _clientFactory = clientFactory;

  static const int pageSize = 60;

  final CredentialStore _credentialStore;
  final MattermostApiFactory _clientFactory;

  @override
  Future<FollowedThreadsPage> loadPage({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async {
    final MattermostApi api = await _apiFor(session);
    final MattermostUserThreadsDto response = await api.getUserThreads(
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
        final List<MattermostUserDto> authors = await api.getUsersByIds(
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
          final MattermostUserDto? author = usersById[post.userId];
          final ChannelPost root = ChannelPost(
            id: post.id,
            channelId: post.channelId,
            author: PostAuthor(
              id: post.userId,
              displayName: author == null ? post.userId : _displayName(author),
            ),
            sentAt: _dateOrEpoch(post.createAt),
            message: post.deleteAt == 0 ? post.message : '',
            replyCount: post.replyCount,
            lastReplyAt: _dateOrNull(post.lastReplyAt),
            isDeleted: post.deleteAt != 0,
          );
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

  Future<MattermostApi> _apiFor(AuthSession session) async {
    final ({Uri serverUrl, String token})? credentials = await _credentialStore
        .read();
    if (credentials == null || credentials.serverUrl != session.serverUrl) {
      throw StateError('No credentials for active Mattermost account');
    }
    return _clientFactory.create(
      serverUrl: credentials.serverUrl,
      token: credentials.token,
    );
  }

  static DateTime _dateOrEpoch(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds);

  static DateTime? _dateOrNull(int milliseconds) =>
      milliseconds == 0 ? null : _dateOrEpoch(milliseconds);

  static String _displayName(MattermostUserDto user) {
    final String fullName = '${user.firstName} ${user.lastName}'.trim();
    if (fullName.isNotEmpty) return fullName;
    if (user.nickname.isNotEmpty) return user.nickname;
    return user.username.isEmpty ? user.id : user.username;
  }
}
