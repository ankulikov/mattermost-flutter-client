import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/messages/data/mattermost_message_mapper.dart';
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
      final _ThreadApi api = _ThreadApi();
      final ApiThreadRepository repository = ApiThreadRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
      );

      final MessageThread thread = await repository.load(
        session: session,
        rootPostId: 'root-1',
      );

      expect(api.threadCalls, 2);
      expect(api.secondFromPost, 'reply-59');
      expect(api.secondFromCreateAt, 2059);
      expect(api.directions, const <PostThreadDirection>[
        PostThreadDirection.up,
        PostThreadDirection.up,
      ]);
      expect(thread.root?.id, 'root-1');
      expect(thread.root?.replyCount, 61);
      expect(thread.replies, hasLength(61));
      expect(thread.replies.first.id, 'reply-0');
      expect(thread.replies.last.id, 'reply-60');
      expect(thread.isComplete, isTrue);
    },
  );

  test('keeps deleted replies returned by the thread endpoint', () async {
    final Uri serverUrl = Uri.parse('https://chat.example.com');
    final AuthSession session = AuthSession(
      serverUrl: serverUrl,
      userId: 'me',
      username: 'current',
    );
    final _ThreadApi api = _ThreadApi(deletedOnly: true);
    final ApiThreadRepository repository = ApiThreadRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
    );

    final MessageThread thread = await repository.load(
      session: session,
      rootPostId: 'root-1',
    );

    expect(thread.replies, hasLength(1));
    expect(thread.replies.single.id, 'deleted-reply');
    expect(thread.replies.single.isDeleted, isTrue);
    expect(thread.replies.single.message, isEmpty);
    expect(thread.replies.single.reactions, isEmpty);
  });
}

final class _ThreadApi implements MattermostApi {
  _ThreadApi({this.deletedOnly = false});

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) => throw UnimplementedError();

  final bool deletedOnly;
  int threadCalls = 0;
  String? secondFromPost;
  int? secondFromCreateAt;
  final List<PostThreadDirection> directions = <PostThreadDirection>[];

  @override
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post) =>
      throw UnimplementedError();

  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) async {
    threadCalls += 1;
    directions.add(direction);
    if (deletedOnly) {
      return MattermostPostListDto(
        order: const <String>['root-1', 'deleted-reply'],
        posts: <String, MattermostPostDto>{
          'root-1': _post('root-1', 1000, replyCount: 1),
          'deleted-reply': _post(
            'deleted-reply',
            2000,
            rootId: 'root-1',
            deleteAt: 3000,
          ),
        },
        nextPostId: '',
        previousPostId: '',
        hasNext: false,
      );
    }
    if (threadCalls == 1) {
      final List<MattermostPostDto> replies = List<MattermostPostDto>.generate(
        60,
        (int index) => _post('reply-$index', 2000 + index, rootId: 'root-1'),
        growable: false,
      );
      return MattermostPostListDto(
        order: <String>[
          'root-1',
          for (final MattermostPostDto reply in replies) reply.id,
        ],
        posts: <String, MattermostPostDto>{
          'root-1': _post('root-1', 1000, replyCount: 61),
          for (final MattermostPostDto reply in replies) reply.id: reply,
        },
        nextPostId: 'reply-59',
        previousPostId: '',
        hasNext: true,
      );
    }
    secondFromPost = fromPost;
    secondFromCreateAt = fromCreateAt;
    return MattermostPostListDto(
      order: const <String>['root-1', 'reply-60'],
      posts: <String, MattermostPostDto>{
        'root-1': _post('root-1', 1000, replyCount: 61),
        'reply-60': _post('reply-60', 2060, rootId: 'root-1'),
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
    int deleteAt = 0,
  }) => MattermostPostDto(
    id: id,
    userId: id == 'reply-2' ? 'grace' : 'ada',
    channelId: 'channel-1',
    message: id,
    createAt: createAt,
    updateAt: createAt,
    deleteAt: deleteAt,
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
