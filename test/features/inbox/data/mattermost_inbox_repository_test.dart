import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example'),
    userId: 'me',
    username: 'me',
  );

  test('deduplicates a direct channel returned by multiple teams', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't1', name: 'one', displayName: 'One'),
        MattermostTeamDto(id: 't2', name: 'two', displayName: 'Two'),
      ],
      channels: <MattermostChannelDto>[
        const MattermostChannelDto(
          id: 'dm',
          teamId: 't1',
          type: 'D',
          name: 'dm',
          displayName: 'DM',
          totalMessageCount: 2,
        ),
      ],
      members: <MattermostChannelMemberDto>[
        const MattermostChannelMemberDto(
          channelId: 'dm',
          userId: 'me',
          msgCount: 1,
        ),
      ],
      unread: <MattermostPostDto>[
        const MattermostPostDto(
          id: 'p1',
          userId: 'other',
          channelId: 'dm',
          message: 'hello',
          createAt: 2,
        ),
      ],
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(snapshot.newItems, hasLength(1));
    expect(snapshot.newItems.single, isA<DirectMessageBundleInboxItem>());
    expect(snapshot.newItems.single.postIds, <String>['p1']);
  });

  test('suppresses a postponed post from New', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: <MattermostChannelDto>[
        const MattermostChannelDto(
          id: 'dm',
          teamId: 't',
          type: 'D',
          name: 'dm',
          displayName: 'DM',
          totalMessageCount: 1,
        ),
      ],
      members: <MattermostChannelMemberDto>[
        const MattermostChannelMemberDto(channelId: 'dm', userId: 'me'),
      ],
      unread: <MattermostPostDto>[
        const MattermostPostDto(
          id: 'p1',
          userId: 'other',
          channelId: 'dm',
          message: 'hello',
          createAt: 1,
        ),
      ],
    );
    final _Postponed postponed = _Postponed(<PostponedReference>[
      PostponedReference(
        postId: 'p1',
        kind: PostponedReferenceKind.post,
        addedAt: DateTime(2026),
      ),
    ]);

    final InboxSnapshot snapshot = await _repository(
      api,
      postponed,
    ).load(session: session);

    expect(snapshot.newItems, isEmpty);
    expect(snapshot.postponedItems.single.postIds, <String>['p1']);
  });

  test('flags incomplete historical mention reconstruction', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: <MattermostChannelDto>[
        const MattermostChannelDto(
          id: 'c',
          teamId: 't',
          type: 'O',
          name: 'c',
          displayName: 'C',
          totalMessageCountRoot: 1,
        ),
      ],
      members: <MattermostChannelMemberDto>[
        const MattermostChannelMemberDto(
          channelId: 'c',
          userId: 'me',
          mentionCountRoot: 1,
        ),
      ],
      unread: <MattermostPostDto>[
        const MattermostPostDto(
          id: 'p1',
          userId: 'other',
          channelId: 'c',
          message: 'not a known mention',
          createAt: 1,
        ),
      ],
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(snapshot.newItems, isEmpty);
    expect(snapshot.hasIncompleteMentionReconstruction, isTrue);
  });

  test(
    'does not fetch ordinary unread channels without mentions or all policy',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'ordinary',
            teamId: 't',
            type: 'O',
            name: 'ordinary',
            displayName: 'Ordinary',
            totalMessageCountRoot: 50,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'ordinary',
            userId: 'me',
            msgCountRoot: 1,
          ),
        ],
        unread: const <MattermostPostDto>[],
      );

      await _repository(api).load(session: session);

      expect(api.unreadChannelIds, isEmpty);
    },
  );

  test(
    'fetches an ordinary unread channel subscribed to all messages',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'all',
            teamId: 't',
            type: 'O',
            name: 'all',
            displayName: 'All',
            totalMessageCountRoot: 2,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'all',
            userId: 'me',
            msgCountRoot: 1,
            notifyProps: MattermostChannelNotifyPropsDto(
              markUnread: 'all',
              desktop: 'all',
            ),
          ),
        ],
        unread: const <MattermostPostDto>[],
      );

      await _repository(api).load(session: session);

      expect(api.unreadChannelIds, <String>['all']);
    },
  );
}

MattermostInboxRepository _repository(
  _InboxApi api, [
  PostponedRepository? postponed,
]) => MattermostInboxRepository(
  api: api,
  messageMapper: const MattermostMessageMapper(),
  postponed: postponed ?? const _Postponed(),
);

final class _InboxApi extends Fake implements MattermostApi {
  _InboxApi({
    required this.teams,
    required this.channels,
    required this.members,
    required this.unread,
  });
  final List<MattermostTeamDto> teams;
  final List<MattermostChannelDto> channels;
  final List<MattermostChannelMemberDto> members;
  final List<MattermostPostDto> unread;
  final List<String> unreadChannelIds = <String>[];
  @override
  Future<MattermostUserDto> getCurrentUser() async =>
      const MattermostUserDto(id: 'me', username: 'me');
  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() async => teams;
  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) async => channels;
  @override
  Future<List<MattermostChannelMemberDto>> getChannelMembersForUser({
    required String userId,
    required String teamId,
  }) async => members;
  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) async => const MattermostUserThreadsDto(
    total: 0,
    totalUnreadThreads: 0,
    totalUnreadMentions: 0,
    threads: <MattermostUserThreadDto>[],
  );
  @override
  Future<MattermostPostListDto> getUnreadPostsForChannel({
    required String userId,
    required String channelId,
    int limitBefore = 0,
    int limitAfter = 200,
  }) async {
    unreadChannelIds.add(channelId);
    return MattermostPostListDto(
      order: unread.map((it) => it.id).toList(),
      posts: {for (final it in unread) it.id: it},
      nextPostId: '',
      previousPostId: '',
      hasNext: false,
    );
  }

  @override
  Future<List<MattermostPostDto>> getPostsByIds(List<String> postIds) async =>
      unread.where((it) => postIds.contains(it.id)).toList();
  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async =>
      const <MattermostUserDto>[
        MattermostUserDto(id: 'other', username: 'other'),
      ];
}

final class _Postponed extends PostponedRepository {
  const _Postponed([this.references = const <PostponedReference>[]]);
  final List<PostponedReference> references;
  @override
  Future<PostponedReferencesSnapshot> load({
    required AuthSession session,
  }) async => PostponedReferencesSnapshot(references);
  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {}
}
