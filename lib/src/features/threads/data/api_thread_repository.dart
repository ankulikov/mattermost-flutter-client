import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/data/mattermost_post_mapper.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final class ApiThreadRepository implements ThreadRepository {
  ApiThreadRepository({
    required CredentialStore credentialStore,
    MattermostApiFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _clientFactory = clientFactory;

  static const int pageSize = 60;
  static const int maxPagesPerLoad = 20;

  final CredentialStore _credentialStore;
  final MattermostApiFactory _clientFactory;

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async {
    final MattermostApi api = await _apiFor(session);
    final Map<String, MattermostPostDto> posts = <String, MattermostPostDto>{};
    String? fromPost;
    int? fromCreateAt;
    var hasNext = true;
    var page = 0;
    while (hasNext && page < maxPagesPerLoad) {
      final MattermostPostListDto response = await api.getPostThread(
        rootPostId: rootPostId,
        perPage: pageSize,
        fromPost: fromPost,
        fromCreateAt: fromCreateAt,
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
        : await api.getUsersByIds(userIds.toList(growable: false));
    final List<ChannelPost> mapped = mapMattermostPosts(
      posts: posts.values,
      users: users,
      currentUserId: session.userId,
    );
    final ChannelPost? root = mapped
        .where((ChannelPost post) => post.id == rootPostId)
        .firstOrNull;
    final List<ChannelPost> replies =
        mapped
            .where((ChannelPost post) => post.rootId == rootPostId)
            .toList(growable: false)
          ..sort(_comparePosts);
    return MessageThread(
      rootPostId: rootPostId,
      root: root,
      replies: List<ChannelPost>.unmodifiable(replies),
      isComplete: !hasNext,
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
