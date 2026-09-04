import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
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

  test(
    'marks channel and direct-message items read by viewing channel',
    () async {
      final _InboxApi api = _emptyApi();
      final MattermostInboxRepository repository = _repository(api);
      final ChannelPostInboxItem item = ChannelPostInboxItem(
        candidate: _candidate('post', direct: true),
      );

      await repository.markRead(session: session, item: item);

      expect(api.viewedChannelId, 'dm');
      expect(api.viewedUserId, 'me');
    },
  );

  test('marks a thread read in its source team at the current time', () async {
    final _InboxApi api = _emptyApi();
    final DateTime now = DateTime.utc(2026, 9, 4, 12);
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: const _Postponed(),
      now: () => now,
    );
    final ThreadInboxItem item = ThreadInboxItem(
      thread: _thread(),
      channel: _channel(),
      teamId: 'source-team',
    );

    await repository.markRead(session: session, item: item);

    expect(api.readThreadId, 'root');
    expect(api.readTeamId, 'source-team');
    expect(api.readTimestamp, now.millisecondsSinceEpoch);
  });
}

_InboxApi _emptyApi() => _InboxApi(
  teams: const <MattermostTeamDto>[],
  channels: const <MattermostChannelDto>[],
  members: const <MattermostChannelMemberDto>[],
  unread: const <MattermostPostDto>[],
);

SidebarChannel _channel({bool direct = false}) => SidebarChannel(
  id: direct ? 'dm' : 'channel',
  teamId: 'team',
  name: 'channel',
  displayName: 'Channel',
  kind: direct ? ChannelKind.directMessage : ChannelKind.publicChannel,
);

InboxPostCandidate _candidate(String id, {bool direct = false}) =>
    InboxPostCandidate(
      post: Post(
        id: id,
        channelId: direct ? 'dm' : 'channel',
        author: const PostAuthor(id: 'other', displayName: 'Other'),
        sentAt: DateTime.utc(2026),
        message: id,
      ),
      channel: _channel(direct: direct),
      reason: InboxAttentionReason.directMention,
    );

FollowedThread _thread() => FollowedThread(
  root: Post(
    id: 'root',
    channelId: 'channel',
    author: const PostAuthor(id: 'other', displayName: 'Other'),
    sentAt: DateTime.utc(2026),
    message: 'Root',
  ),
  replyCount: 1,
  lastReplyAt: DateTime.utc(2026),
  lastViewedAt: DateTime.utc(2025),
  unreadReplies: 1,
  unreadMentions: 0,
);

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
  String? viewedChannelId;
  String? viewedUserId;
  String? readThreadId;
  String? readTeamId;
  int? readTimestamp;
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

  @override
  Future<void> viewChannel({
    required String userId,
    required String channelId,
    String? previousChannelId,
  }) async {
    viewedUserId = userId;
    viewedChannelId = channelId;
  }

  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) async {
    readTeamId = teamId;
    readThreadId = threadId;
    readTimestamp = timestamp;
  }
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
