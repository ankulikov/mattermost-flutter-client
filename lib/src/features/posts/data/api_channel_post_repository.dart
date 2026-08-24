import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/data/mattermost_post_mapper.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final class ApiChannelPostRepository implements ChannelPostRepository {
  ApiChannelPostRepository({
    required CredentialStore credentialStore,
    MattermostApiFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _clientFactory = clientFactory;

  static const int pageSize = 60;

  final CredentialStore _credentialStore;
  final MattermostApiFactory _clientFactory;

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async {
    final MattermostApi api = await _apiFor(session);
    final MattermostPostListDto response = await api.getPostsForChannel(
      channelId: channelId,
      perPage: pageSize,
    );
    return _mapPage(api: api, session: session, response: response);
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async {
    final MattermostApi api = await _apiFor(session);
    final MattermostPostListDto response = await api.getPostsBefore(
      channelId: channelId,
      postId: beforePostId,
      perPage: pageSize,
    );
    return _mapPage(api: api, session: session, response: response);
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
    final List<ChannelPost> roots =
        mapMattermostPosts(
            posts: orderedPosts,
            users: users,
            currentUserId: session.userId,
          ).where((ChannelPost post) => !post.isReply).toList(growable: false)
          ..sort(_comparePosts);
    final String? beforePostId = response.order.lastOrNull;
    return ChannelPostPage(
      posts: List<ChannelPost>.unmodifiable(roots),
      beforePostId: beforePostId,
      hasOlder: beforePostId != null && response.previousPostId.isNotEmpty,
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

  static int _comparePosts(ChannelPost a, ChannelPost b) {
    final int byTime = a.sentAt.compareTo(b.sentAt);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}
