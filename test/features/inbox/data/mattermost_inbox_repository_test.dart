import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/websocket_gateway.dart';
import 'package:mattermost_flutter/src/data/storage/credential_store.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/data/repositories/mattermost_inbox_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
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

  test(
    'resolves direct and group dialog names before Inbox navigation',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 'team', displayName: 'Team'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'direct',
            teamId: 't',
            type: 'D',
            name: 'me__ada',
            displayName: '',
            totalMessageCount: 1,
          ),
          MattermostChannelDto(
            id: 'group',
            teamId: 't',
            type: 'G',
            name: 'me__ada__grace',
            displayName: '',
            totalMessageCount: 1,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'direct', userId: 'me'),
          MattermostChannelMemberDto(channelId: 'group', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[
          MattermostPostDto(
            id: 'direct-post',
            userId: 'ada',
            channelId: 'direct',
            message: 'Hi',
            createAt: 1,
          ),
          MattermostPostDto(
            id: 'group-post',
            userId: 'grace',
            channelId: 'group',
            message: 'Hello',
            createAt: 2,
          ),
        ],
        users: const <MattermostUserDto>[
          MattermostUserDto(id: 'ada', username: 'ada', firstName: 'Ada'),
          MattermostUserDto(id: 'grace', username: 'grace', firstName: 'Grace'),
        ],
        groupUsers: const MattermostGroupChannelUsersDto(
          usersByChannelId: <String, List<MattermostUserDto>>{
            'group': <MattermostUserDto>[
              MattermostUserDto(id: 'me', username: 'me'),
              MattermostUserDto(id: 'ada', username: 'ada', firstName: 'Ada'),
              MattermostUserDto(
                id: 'grace',
                username: 'grace',
                firstName: 'Grace',
              ),
            ],
          },
        ),
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);
      final List<SidebarChannel> channels = snapshot.newItems
          .map(
            (InboxItem item) => switch (item) {
              DirectMessageBundleInboxItem(:final messages) =>
                messages.first.channel,
              ChannelPostInboxItem(:final candidate) => candidate.channel,
              ThreadInboxItem(:final channel) => channel,
            },
          )
          .toList(growable: false);

      expect(
        channels
            .singleWhere((SidebarChannel channel) => channel.id == 'direct')
            .displayName,
        'Ada',
      );
      expect(
        channels
            .singleWhere((SidebarChannel channel) => channel.id == 'group')
            .displayName,
        'Ada, Grace',
      );
    },
  );

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

  test(
    'maps only current-username realtime mentions in known channels',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 'team', name: 'team', displayName: 'Team'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'channel',
            teamId: 'team',
            type: 'O',
            name: 'channel',
            displayName: 'Channel',
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'channel', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[],
      );
      final _Gateway gateway = _Gateway();
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
        webSocketGateway: gateway,
        credentialStore: _Credentials(session.serverUrl),
      );
      await repository.load(session: session);
      final List<InboxRealtimeEvent> events = <InboxRealtimeEvent>[];
      final StreamSubscription<InboxRealtimeEvent> subscription = repository
          .watch(session: session)
          .listen(events.add);
      addTearDown(() async {
        await gateway.close();
        await subscription.cancel();
      });
      await _waitUntil(() => gateway.started);

      expect(gateway.acceptsEvent?.call('posted'), isTrue);
      expect(gateway.acceptsEvent?.call('typing'), isFalse);
      expect(gateway.acceptsChannel?.call('channel'), isTrue);
      expect(gateway.acceptsChannel?.call('unrelated'), isFalse);

      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'realtime',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'hello @me',
                'create_at': 1,
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      await _waitUntil(() => events.whereType<InboxPostChanged>().isNotEmpty);

      final InboxPostChanged changed = events
          .whereType<InboxPostChanged>()
          .single;
      expect(changed.postId, 'realtime');
      expect(changed.candidate?.reason, InboxAttentionReason.directMention);

      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 2,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'not-a-mention',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'hello everyone',
                'create_at': 2,
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      await _waitUntil(() => events.whereType<InboxPostChanged>().length == 2);
      expect(events.whereType<InboxPostChanged>().last.candidate, isNull);
    },
  );

  test(
    'requests HTTP recovery only after reconnect or a sequence gap',
    () async {
      final _Gateway gateway = _Gateway();
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 'team', name: 'team', displayName: 'Team'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'channel',
            teamId: 'team',
            type: 'O',
            name: 'channel',
            displayName: 'Channel',
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'channel', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[],
        failUserLookup: true,
      );
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
        webSocketGateway: gateway,
        credentialStore: _Credentials(session.serverUrl),
      );
      await repository.load(session: session);
      final List<InboxRealtimeEvent> events = <InboxRealtimeEvent>[];
      final StreamSubscription<InboxRealtimeEvent> subscription = repository
          .watch(session: session)
          .listen(events.add);
      addTearDown(() async {
        await gateway.close();
        await subscription.cancel();
      });
      await _waitUntil(() => gateway.started);

      gateway.add(
        const WebSocketConnectionSignal(
          status: WebSocketConnectionStatus.connected,
        ),
      );
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'reply',
                'root_id': 'root',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'reply',
                'create_at': 1,
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      for (final String name in <String>[
        'thread_updated',
        'thread_read_changed',
        'preference_changed',
      ]) {
        gateway.add(
          WebSocketEventSignal(
            MattermostWebSocketEvent(
              name: name,
              sequence: 2,
              data: const <String, Object?>{},
              broadcast: const <String, Object?>{},
            ),
          ),
        );
      }
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 3,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'mapping-fails',
                'user_id': 'unknown-author',
                'channel_id': 'channel',
                'message': 'hello @me',
                'create_at': 2,
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      gateway.add(
        const WebSocketConnectionSignal(
          status: WebSocketConnectionStatus.disconnected,
        ),
      );
      await _waitUntil(
        () => events.whereType<InboxConnectionChanged>().length == 2,
      );

      expect(events.whereType<InboxRefreshRequired>(), isEmpty);

      gateway.add(
        const WebSocketConnectionSignal(
          status: WebSocketConnectionStatus.connected,
          isReconnect: true,
        ),
      );
      await _waitUntil(
        () => events.whereType<InboxRefreshRequired>().length == 1,
      );
      gateway.add(const WebSocketSequenceGapSignal(expected: 3, actual: 4));
      await _waitUntil(
        () => events.whereType<InboxRefreshRequired>().length == 2,
      );
    },
  );
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
    this.users = const <MattermostUserDto>[
      MattermostUserDto(id: 'other', username: 'other'),
    ],
    this.groupUsers = const MattermostGroupChannelUsersDto(
      usersByChannelId: <String, List<MattermostUserDto>>{},
    ),
    this.failUserLookup = false,
  });
  final List<MattermostTeamDto> teams;
  final List<MattermostChannelDto> channels;
  final List<MattermostChannelMemberDto> members;
  final List<MattermostPostDto> unread;
  final List<MattermostUserDto> users;
  final MattermostGroupChannelUsersDto groupUsers;
  final bool failUserLookup;
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
    final List<MattermostPostDto> channelPosts = unread
        .where((MattermostPostDto post) => post.channelId == channelId)
        .toList(growable: false);
    return MattermostPostListDto(
      order: channelPosts.map((MattermostPostDto post) => post.id).toList(),
      posts: {for (final MattermostPostDto post in channelPosts) post.id: post},
      nextPostId: '',
      previousPostId: '',
      hasNext: false,
    );
  }

  @override
  Future<List<MattermostPostDto>> getPostsByIds(List<String> postIds) async =>
      unread.where((it) => postIds.contains(it.id)).toList();
  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    if (failUserLookup) throw StateError('profile lookup failed');
    return users
        .where((MattermostUserDto user) => userIds.contains(user.id))
        .toList();
  }

  @override
  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  ) async => groupUsers;

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

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 100; index++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached');
}

final class _Gateway implements WebSocketGateway {
  final StreamController<WebSocketGatewaySignal> _signals =
      StreamController<WebSocketGatewaySignal>();
  bool Function(String)? acceptsEvent;
  bool Function(String)? acceptsChannel;
  bool started = false;

  @override
  Stream<WebSocketGatewaySignal> watch({
    required Uri serverUrl,
    required String token,
    required bool Function(String eventName) acceptsEvent,
    required bool Function(String channelId) acceptsChannel,
  }) {
    this.acceptsEvent = acceptsEvent;
    this.acceptsChannel = acceptsChannel;
    started = true;
    return _signals.stream;
  }

  void add(WebSocketGatewaySignal signal) => _signals.add(signal);

  Future<void> close() => _signals.close();
}

final class _Credentials implements CredentialStore {
  const _Credentials(this.serverUrl);

  final Uri serverUrl;

  @override
  Future<void> clear() async {}

  @override
  Future<({Uri serverUrl, String token})?> read() async =>
      (serverUrl: serverUrl, token: 'test-credential');

  @override
  Future<void> save({required Uri serverUrl, required String token}) async {}
}
