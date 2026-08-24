import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/data/channel_post_cache_models.dart';
import 'package:mattermost_flutter/src/features/posts/data/channel_post_store.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final class ApiChannelPostRepository implements ChannelPostRepository {
  ApiChannelPostRepository({
    required CredentialStore credentialStore,
    required ChannelPostStore store,
    MattermostApiFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _store = store,
       _clientFactory = clientFactory;

  static const int pageSize = 60;

  final CredentialStore _credentialStore;
  final ChannelPostStore _store;
  final MattermostApiFactory _clientFactory;

  @override
  Stream<ChannelPostSnapshot> watch({
    required String accountId,
    required String channelId,
  }) => _store.watch(accountId: accountId, channelId: channelId);

  @override
  Future<ChannelPostSnapshot> read({
    required String accountId,
    required String channelId,
  }) => _store.read(accountId: accountId, channelId: channelId);

  @override
  Future<ChannelPostRefreshResult> refreshLatest({
    required AuthSession session,
    required String channelId,
  }) async {
    final ChannelPostSnapshot before = await read(
      accountId: session.accountId,
      channelId: channelId,
    );
    final MattermostApi api = await _apiFor(session);
    final MattermostPostListDto response = await api.getPostsForChannel(
      channelId: channelId,
      perPage: pageSize,
    );
    await _saveResponse(
      api: api,
      session: session,
      channelId: channelId,
      response: response,
      isLatestPage: true,
    );
    final Set<String> knownIds = before.posts.map((post) => post.id).toSet();
    return ChannelPostRefreshResult(
      newPostIds: response.order
          .where(
            (String id) =>
                response.posts[id]?.rootId.isEmpty == true &&
                !knownIds.contains(id),
          )
          .toSet(),
    );
  }

  @override
  Future<void> loadOlder({
    required AuthSession session,
    required String channelId,
  }) async {
    final String? oldestId = await _store.oldestPostId(
      accountId: session.accountId,
      channelId: channelId,
    );
    if (oldestId == null) return;
    final MattermostApi api = await _apiFor(session);
    final MattermostPostListDto response = await api.getPostsBefore(
      channelId: channelId,
      postId: oldestId,
      perPage: pageSize,
    );
    await _saveResponse(
      api: api,
      session: session,
      channelId: channelId,
      response: response,
      isLatestPage: false,
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

  Future<void> _saveResponse({
    required MattermostApi api,
    required AuthSession session,
    required String channelId,
    required MattermostPostListDto response,
    required bool isLatestPage,
  }) async {
    final List<MattermostPostDto> orderedPosts = response.order
        .map((String id) => response.posts[id])
        .whereType<MattermostPostDto>()
        .toList(growable: false);
    final Set<String> userIds = orderedPosts
        .map((MattermostPostDto post) => post.userId)
        .where((String id) => id.isNotEmpty)
        .toSet();
    final List<MattermostUserDto> users = await api.getUsersByIds(
      userIds.toList(growable: false),
    );
    await _store.savePage(
      accountId: session.accountId,
      channelId: channelId,
      page: PostCachePage(
        order: response.order,
        oldestComplete: response.previousPostId.isEmpty,
        authors: users
            .map(
              (MattermostUserDto user) =>
                  PostCacheAuthor(id: user.id, displayName: _displayName(user)),
            )
            .toList(growable: false),
        posts: orderedPosts
            .map((MattermostPostDto post) => _mapPost(post, session.userId))
            .toList(growable: false),
      ),
      isLatestPage: isLatestPage,
    );
  }

  static PostCacheItem _mapPost(MattermostPostDto post, String currentUserId) {
    final Map<String, List<MattermostReactionDto>> grouped =
        <String, List<MattermostReactionDto>>{};
    for (final MattermostReactionDto reaction
        in post.metadata?.reactions ?? const <MattermostReactionDto>[]) {
      grouped
          .putIfAbsent(reaction.emojiName, () => <MattermostReactionDto>[])
          .add(reaction);
    }
    return PostCacheItem(
      id: post.id,
      channelId: post.channelId,
      userId: post.userId,
      createAt: post.createAt,
      updateAt: post.updateAt,
      deleteAt: post.deleteAt,
      message: post.message,
      rootId: post.rootId,
      replyCount: post.replyCount,
      lastReplyAt: post.lastReplyAt,
      reactions: grouped.entries
          .map(
            (MapEntry<String, List<MattermostReactionDto>> entry) =>
                PostCacheReaction(
                  emojiName: entry.key,
                  count: entry.value.length,
                  reactedByCurrentUser: entry.value.any(
                    (MattermostReactionDto reaction) =>
                        reaction.userId == currentUserId,
                  ),
                ),
          )
          .toList(growable: false),
    );
  }

  static String _displayName(MattermostUserDto user) {
    final String fullName = '${user.firstName} ${user.lastName}'.trim();
    if (fullName.isNotEmpty) return fullName;
    if (user.nickname.isNotEmpty) return user.nickname;
    return user.username.isEmpty ? user.id : user.username;
  }
}
