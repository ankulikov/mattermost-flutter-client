import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/data/api_channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/data/channel_post_cache_models.dart';
import 'package:mattermost_flutter/src/features/posts/data/channel_post_store.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

void main() {
  test(
    'refreshes page 0 and pages older posts from the stored cursor',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final ChannelPostStore store = ChannelPostStore(database);
      addTearDown(store.close);
      await store.savePage(
        accountId: session.accountId,
        channelId: 'channel-1',
        page: PostCachePage(
          posts: <PostCacheItem>[_cachePost('post-1', 1000)],
          authors: const <PostCacheAuthor>[
            PostCacheAuthor(id: 'ada', displayName: 'Ada'),
          ],
          order: const <String>['post-1'],
          oldestComplete: false,
        ),
        isLatestPage: true,
      );
      final _FakePostApi api = _FakePostApi();
      final ApiChannelPostRepository repository = ApiChannelPostRepository(
        credentialStore: _CredentialStore(serverUrl),
        store: store,
        clientFactory: _ApiFactory(api),
      );

      final ChannelPostRefreshResult refresh = await repository.refreshLatest(
        session: session,
        channelId: 'channel-1',
      );
      expect(refresh.newPostIds, const <String>{'post-2'});
      expect(api.latestPerPage, ApiChannelPostRepository.pageSize);

      await repository.loadOlder(session: session, channelId: 'channel-1');
      expect(api.beforeId, 'post-1');
      final ChannelPostSnapshot snapshot = await repository.read(
        accountId: session.accountId,
        channelId: 'channel-1',
      );
      expect(snapshot.posts.map((post) => post.id), const <String>[
        'post-0',
        'post-1',
        'post-2',
      ]);
      expect(snapshot.hasOlder, isFalse);
    },
  );
}

PostCacheItem _cachePost(String id, int createAt) => PostCacheItem(
  id: id,
  channelId: 'channel-1',
  userId: 'ada',
  createAt: createAt,
  updateAt: createAt,
  deleteAt: 0,
  message: id,
  reactions: const <PostCacheReaction>[],
);

final class _CredentialStore implements CredentialStore {
  const _CredentialStore(this.serverUrl);

  final Uri serverUrl;

  @override
  Future<void> clear() async {}

  @override
  Future<({Uri serverUrl, String token})?> read() async =>
      (serverUrl: serverUrl, token: 'token');

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {}
}

final class _ApiFactory implements MattermostApiFactory {
  const _ApiFactory(this.api);

  final MattermostApi api;

  @override
  MattermostApi create({required Uri serverUrl, required String token}) => api;
}

final class _FakePostApi implements MattermostApi {
  int? latestPerPage;
  String? beforeId;

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) async {
    latestPerPage = perPage;
    return MattermostPostListDto(
      order: const <String>['reply-2', 'post-2', 'post-1'],
      posts: <String, MattermostPostDto>{
        'reply-2': _post('reply-2', 2100, rootId: 'post-1'),
        'post-2': _post('post-2', 2000),
        'post-1': _post('post-1', 1000),
      },
      nextPostId: '',
      previousPostId: 'post-0',
      hasNext: false,
    );
  }

  @override
  Future<MattermostPostListDto> getPostsBefore({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) async {
    beforeId = postId;
    return MattermostPostListDto(
      order: const <String>['post-0'],
      posts: <String, MattermostPostDto>{'post-0': _post('post-0', 0)},
      nextPostId: '',
      previousPostId: '',
      hasNext: false,
    );
  }

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async =>
      const <MattermostUserDto>[
        MattermostUserDto(id: 'ada', username: 'ada', firstName: 'Ada'),
      ];

  MattermostPostDto _post(String id, int createAt, {String rootId = ''}) =>
      MattermostPostDto(
        id: id,
        userId: 'ada',
        channelId: 'channel-1',
        message: id,
        createAt: createAt,
        updateAt: createAt,
        rootId: rootId,
      );

  @override
  Future<MattermostChannelCategoriesDto> getChannelCategories({
    required String userId,
    required String teamId,
  }) => throw UnimplementedError();

  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) => throw UnimplementedError();

  @override
  Future<MattermostUserDto> getCurrentUser() => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsSince({
    required String channelId,
    required int since,
  }) => throw UnimplementedError();

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() =>
      throw UnimplementedError();

  @override
  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  ) => throw UnimplementedError();
}
