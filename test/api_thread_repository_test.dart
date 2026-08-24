import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/threads/data/api_thread_repository.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';

void main() {
  test(
    'paginates a thread and atomically exposes its root and replies',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final _ThreadApi api = _ThreadApi();
      final ApiThreadRepository repository = ApiThreadRepository(
        credentialStore: _Credentials(serverUrl),
        database: database,
        clientFactory: _ApiFactory(api),
      );

      await repository.refresh(session: session, rootPostId: 'root-1');
      final MessageThread thread = await repository.read(
        accountId: session.accountId,
        rootPostId: 'root-1',
      );

      expect(api.threadCalls, 2);
      expect(api.secondFromPost, 'reply-1');
      expect(thread.root?.id, 'root-1');
      expect(thread.root?.replyCount, 2);
      expect(thread.replies.map((post) => post.id), const <String>[
        'reply-2',
        'reply-1',
      ]);
      expect(thread.isComplete, isTrue);
    },
  );
}

final class _Credentials implements CredentialStore {
  const _Credentials(this.serverUrl);

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

final class _ThreadApi implements MattermostApi {
  int threadCalls = 0;
  String? secondFromPost;

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
  }) async {
    threadCalls += 1;
    if (threadCalls == 1) {
      return MattermostPostListDto(
        order: const <String>['root-1', 'reply-1'],
        posts: <String, MattermostPostDto>{
          'root-1': _post('root-1', 1000, replyCount: 2),
          'reply-1': _post('reply-1', 3000, rootId: 'root-1'),
        },
        nextPostId: 'reply-1',
        previousPostId: '',
        hasNext: true,
      );
    }
    secondFromPost = fromPost;
    return MattermostPostListDto(
      order: const <String>['root-1', 'reply-2'],
      posts: <String, MattermostPostDto>{
        'root-1': _post('root-1', 1000, replyCount: 2),
        'reply-2': _post('reply-2', 2000, rootId: 'root-1'),
      },
      nextPostId: '',
      previousPostId: '',
      hasNext: false,
    );
  }

  MattermostPostDto _post(
    String id,
    int createAt, {
    String rootId = '',
    int replyCount = 0,
  }) => MattermostPostDto(
    id: id,
    userId: id == 'reply-2' ? 'grace' : 'ada',
    channelId: 'channel-1',
    message: id,
    createAt: createAt,
    updateAt: createAt,
    rootId: rootId,
    replyCount: replyCount,
  );

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async =>
      const <MattermostUserDto>[
        MattermostUserDto(id: 'ada', username: 'ada', firstName: 'Ada'),
        MattermostUserDto(id: 'grace', username: 'grace', firstName: 'Grace'),
      ];

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
  Future<MattermostPostListDto> getPostsBefore({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) => throw UnimplementedError();

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
