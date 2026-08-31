import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/repositories/api_followed_threads_repository.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';

import 'support/fake_user_repository.dart';

void main() {
  test(
    'loads thread summaries and batches only missing root authors',
    () async {
      final Uri serverUrl = Uri.parse('https://chat.example.com');
      final _ThreadsApi api = _ThreadsApi();
      final FakeUserRepository users = FakeUserRepository();
      final ApiFollowedThreadsRepository repository =
          ApiFollowedThreadsRepository(
            api: api,
            messageMapper: const MattermostMessageMapper(),
            users: users,
          );

      final FollowedThreadsPage page = await repository.loadPage(
        session: AuthSession(
          serverUrl: serverUrl,
          userId: 'me',
          username: 'current',
        ),
        teamId: 'team-1',
        before: 'older-root',
      );

      expect(api.threadCalls, 1);
      expect(api.perPage, 60);
      expect(api.before, 'older-root');
      expect(api.extended, isTrue);
      expect(users.requestedIdBatches, <List<String>>[
        <String>['missing-author'],
      ]);
      expect(page.total, 2);
      expect(page.totalUnreadThreads, 2);
      expect(page.totalUnreadMentions, 1);
      expect(page.items, hasLength(2));
      expect(page.items.first.root.author.displayName, 'Ada Lovelace');
      expect(page.items.first.unreadMentions, 1);
      expect(page.items.last.root.author.displayName, 'Grace Hopper');
      expect(page.items.last.unreadReplies, 3);
    },
  );
}

final class _ThreadsApi implements MattermostApi {
  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) => throw UnimplementedError();

  @override
  Future<MattermostPostDto> createPost(MattermostCreatePostRequestDto post) =>
      throw UnimplementedError();

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) => throw UnimplementedError();

  int threadCalls = 0;
  int? perPage;
  String? before;
  bool? extended;
  final List<List<String>> userIdBatches = <List<String>>[];

  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) async {
    threadCalls += 1;
    this.perPage = perPage;
    this.before = before;
    this.extended = extended;
    return MattermostUserThreadsDto(
      total: 2,
      totalUnreadThreads: 2,
      totalUnreadMentions: 1,
      threads: <MattermostUserThreadDto>[
        MattermostUserThreadDto(
          id: 'root-1',
          replyCount: 4,
          lastReplyAt: 4000,
          lastViewedAt: 3000,
          participants: const <MattermostUserDto>[
            MattermostUserDto(
              id: 'ada',
              username: 'ada',
              firstName: 'Ada',
              lastName: 'Lovelace',
            ),
          ],
          post: _post('root-1', 'ada'),
          unreadReplies: 2,
          unreadMentions: 1,
        ),
        MattermostUserThreadDto(
          id: 'root-2',
          replyCount: 7,
          lastReplyAt: 5000,
          lastViewedAt: 2000,
          participants: const <MattermostUserDto>[],
          post: _post('root-2', 'missing-author'),
          unreadReplies: 3,
          unreadMentions: 0,
        ),
      ],
    );
  }

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    userIdBatches.add(userIds);
    return const <MattermostUserDto>[
      MattermostUserDto(
        id: 'missing-author',
        username: 'grace',
        firstName: 'Grace',
        lastName: 'Hopper',
      ),
    ];
  }

  MattermostPostDto _post(String id, String userId) => MattermostPostDto(
    id: id,
    userId: userId,
    channelId: 'town-square',
    message: 'Message $id',
    createAt: 1000,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
