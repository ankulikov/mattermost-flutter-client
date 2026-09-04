import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/repositories/mattermost_post_repository.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';

import 'support/fake_user_repository.dart';

void main() {
  test(
    'loads latest roots and pages older posts from the raw cursor',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );
      final _FakePostApi api = _FakePostApi();
      final MattermostPostRepository repository = MattermostPostRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        users: FakeUserRepository(),
      );

      final ChannelPostPage latest = await repository.loadLatest(
        session: session,
        channelId: 'channel-1',
      );
      expect(api.latestPerPage, MattermostPostRepository.pageSize);
      expect(latest.posts.map((post) => post.id), const <String>[
        'post-1',
        'post-2',
      ]);
      expect(latest.posts.first.replyCount, 1);
      expect(latest.posts.first.author.profileImageUpdatedAt, 99);
      expect(
        latest.posts.first.lastReplyAt,
        DateTime.fromMillisecondsSinceEpoch(2100),
      );
      expect(latest.replySummaries['post-1']?.replyIds, const <String>{
        'reply-2',
      });
      expect(latest.beforePostId, 'post-1');
      expect(latest.hasOlder, isTrue);

      final ChannelPostPage older = await repository.loadOlder(
        session: session,
        channelId: 'channel-1',
        beforePostId: latest.beforePostId!,
      );
      expect(api.beforeId, 'post-1');
      expect(older.posts.single.id, 'post-0');
      expect(older.hasOlder, isFalse);
    },
  );

  test(
    'advances pagination when the latest page contains only replies',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final AuthSession session = AuthSession(
        serverUrl: serverUrl,
        userId: 'me',
        username: 'current',
      );
      final _FakePostApi api = _FakePostApi(hasReplyOnlyLatest: true);
      final MattermostPostRepository repository = MattermostPostRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        users: FakeUserRepository(),
      );

      final ChannelPostPage latest = await repository.loadLatest(
        session: session,
        channelId: 'channel-1',
      );

      expect(latest.posts, isEmpty);
      expect(latest.replySummaries['missing-root']?.replyIds, const <String>{
        'reply-2',
        'reply-3',
      });
      expect(latest.beforePostId, 'reply-2');
      expect(latest.hasOlder, isTrue);
    },
  );
}

final class _FakePostApi implements MattermostApi {
  _FakePostApi({this.hasReplyOnlyLatest = false});

  @override
  Future<List<MattermostUserDto>> getUsersByUsernames(List<String> usernames) =>
      throw UnimplementedError();

  @override
  Future<void> saveReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) => throw UnimplementedError();

  @override
  Future<MattermostChannelDto> createDirectChannel({
    required String currentUserId,
    required String otherUserId,
  }) => throw UnimplementedError();

  @override
  Future<MattermostUserStatusDto> getUserStatus(String userId) =>
      throw UnimplementedError();

  @override
  Future<MattermostUserDto> getUserById(String userId) =>
      throw UnimplementedError();

  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) => throw UnimplementedError();

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) => throw UnimplementedError();

  @override
  Future<MattermostEmojiDto> getCustomEmojiByName(String name) =>
      throw UnimplementedError();

  @override
  Future<MattermostImageDto> getCustomEmojiImage(String emojiId) =>
      throw UnimplementedError();

  @override
  Future<MattermostFileContentDto> getFile(String fileId) =>
      throw UnimplementedError();

  @override
  Future<MattermostFileContentDto> getFilePreview(String fileId) =>
      throw UnimplementedError();

  @override
  Future<MattermostFileContentDto> getFileThumbnail(String fileId) =>
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

  final bool hasReplyOnlyLatest;
  int? latestPerPage;
  String? beforeId;

  @override
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post) =>
      throw UnimplementedError();

  @override
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) async {
    latestPerPage = perPage;
    if (hasReplyOnlyLatest) {
      return MattermostPostListDto(
        order: const <String>['reply-3', 'reply-2'],
        posts: <String, MattermostPostDto>{
          'reply-3': _post('reply-3', 3000, rootId: 'missing-root'),
          'reply-2': _post('reply-2', 2000, rootId: 'missing-root'),
        },
        nextPostId: '',
        previousPostId: 'post-1',
        hasNext: false,
      );
    }
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
        MattermostUserDto(
          id: 'ada',
          username: 'ada',
          firstName: 'Ada',
          lastPictureUpdate: 99,
        ),
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
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) => throw UnimplementedError();

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
