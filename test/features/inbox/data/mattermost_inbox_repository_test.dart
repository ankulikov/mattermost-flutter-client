import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/database/user_group_membership_cache.dart';
import 'package:mattermost_flutter/src/data/mappers/mattermost_message_mapper.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
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
import 'package:mattermost_flutter/src/features/inbox/domain/models/viewed_channel_posts.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/viewed_channel_posts_repository.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri.parse('https://chat.example'),
    userId: 'me',
    username: 'me',
  );

  test('requests only unread followed threads for Inbox', () async {
    const MattermostUserThreadDto readThread = MattermostUserThreadDto(
      id: 'read-root',
      replyCount: 0,
      lastReplyAt: 1,
      lastViewedAt: 1,
      participants: <MattermostUserDto>[],
      unreadReplies: 0,
      unreadMentions: 0,
      post: MattermostPostDto(
        id: 'read-root',
        userId: 'other',
        channelId: 'channel',
        message: 'Read',
        createAt: 1,
      ),
    );
    const MattermostUserThreadDto unreadThread = MattermostUserThreadDto(
      id: 'unread-root',
      replyCount: 1,
      lastReplyAt: 2,
      lastViewedAt: 1,
      participants: <MattermostUserDto>[],
      unreadReplies: 1,
      unreadMentions: 0,
      post: MattermostPostDto(
        id: 'unread-root',
        userId: 'other',
        channelId: 'channel',
        message: 'Unread',
        createAt: 2,
      ),
    );
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
      threadPages: const <List<MattermostUserThreadDto>>[
        <MattermostUserThreadDto>[readThread],
        <MattermostUserThreadDto>[unreadThread],
      ],
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(api.requestedThreadCursors, <String?>[null]);
    expect(api.requestedUnreadFilters, <bool>[true]);
    expect(snapshot.newItems, hasLength(1));
    expect(snapshot.newItems.single, isA<ThreadInboxItem>());
    expect(
      (snapshot.newItems.single as ThreadInboxItem).thread.id,
      'unread-root',
    );
  });

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

  test('keeps each postponed direct message add time after reload', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: const <MattermostChannelDto>[
        MattermostChannelDto(
          id: 'dm',
          teamId: 't',
          type: 'D',
          name: 'dm',
          displayName: 'DM',
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(channelId: 'dm', userId: 'me'),
      ],
      unread: const <MattermostPostDto>[
        MattermostPostDto(
          id: 'older',
          userId: 'other',
          channelId: 'dm',
          message: 'Older message',
          createAt: 1,
        ),
        MattermostPostDto(
          id: 'newer',
          userId: 'other',
          channelId: 'dm',
          message: 'Newer message',
          createAt: 2,
        ),
      ],
    );
    final DateTime firstAdded = DateTime.utc(2026, 9);
    final DateTime lastAdded = firstAdded.add(const Duration(days: 1));
    final InboxSnapshot snapshot = await _repository(
      api,
      _Postponed(<PostponedReference>[
        PostponedReference(
          postId: 'newer',
          kind: PostponedReferenceKind.post,
          addedAt: firstAdded,
        ),
        PostponedReference(
          postId: 'older',
          kind: PostponedReferenceKind.post,
          addedAt: lastAdded,
        ),
      ]),
    ).load(session: session);

    expect(
      snapshot.postponedItems.map((InboxItem item) => item.postIds.single),
      <String>['older', 'newer'],
    );
    expect(
      snapshot.postponedItems.map((InboxItem item) => item.postponedAt),
      <DateTime>[lastAdded, firstAdded],
    );
  });

  test('hydrates a specifically postponed reply as its own item', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 'team', displayName: 'Team'),
      ],
      channels: const <MattermostChannelDto>[
        MattermostChannelDto(
          id: 'channel',
          teamId: 't',
          type: 'O',
          name: 'channel',
          displayName: 'Channel',
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(channelId: 'channel', userId: 'me'),
      ],
      unread: const <MattermostPostDto>[
        MattermostPostDto(
          id: 'reply',
          rootId: 'root',
          userId: 'other',
          channelId: 'channel',
          message: 'The selected reply',
          createAt: 2,
        ),
      ],
    );
    final InboxSnapshot snapshot = await _repository(
      api,
      _Postponed(<PostponedReference>[
        PostponedReference(
          postId: 'reply',
          kind: PostponedReferenceKind.post,
          addedAt: DateTime.utc(2026),
        ),
      ]),
    ).load(session: session);

    final ChannelPostInboxItem item =
        snapshot.postponedItems.single as ChannelPostInboxItem;
    expect(item.post.id, 'reply');
    expect(item.post.message, 'The selected reply');
  });

  test('restores a postponed group mention source', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 'team', displayName: 'Team'),
      ],
      channels: const <MattermostChannelDto>[
        MattermostChannelDto(
          id: 'channel',
          teamId: 't',
          type: 'O',
          name: 'channel',
          displayName: 'Channel',
          totalMessageCountRoot: 1,
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'channel',
          userId: 'me',
          mentionCountRoot: 1,
        ),
      ],
      unread: const <MattermostPostDto>[
        MattermostPostDto(
          id: 'group-post',
          userId: 'other',
          channelId: 'channel',
          message: 'hello @backend',
          createAt: 1,
        ),
      ],
      groups: const <MattermostGroupDto>[
        MattermostGroupDto(
          id: 'group',
          name: 'backend',
          displayName: 'Backend',
          allowReference: true,
        ),
      ],
    );
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: _Postponed(<PostponedReference>[
        PostponedReference(
          postId: 'group-post',
          kind: PostponedReferenceKind.post,
          addedAt: DateTime.utc(2026),
        ),
      ]),
      userGroupCache: _GroupCache(),
    );

    final InboxSnapshot snapshot = await repository.load(session: session);

    final ChannelPostInboxItem item =
        snapshot.postponedItems.single as ChannelPostInboxItem;
    expect(item.candidate.reason, InboxAttentionReason.groupMention);
    expect(item.candidate.groupMentionHandle, '@backend');
  });

  test(
    'hydrates unread thread replies and preserves personal and group reasons',
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
        groups: const <MattermostGroupDto>[
          MattermostGroupDto(
            id: 'group',
            name: 'backend',
            displayName: 'Backend',
            allowReference: true,
          ),
        ],
        threads: const <MattermostUserThreadDto>[
          MattermostUserThreadDto(
            id: 'root',
            replyCount: 3,
            lastReplyAt: 3000,
            lastViewedAt: 1000,
            participants: <MattermostUserDto>[],
            post: MattermostPostDto(
              id: 'root',
              userId: 'other',
              channelId: 'channel',
              message: 'Root',
              createAt: 500,
            ),
            unreadReplies: 2,
            unreadMentions: 2,
          ),
        ],
        threadPosts: const <String, List<MattermostPostDto>>{
          'root': <MattermostPostDto>[
            MattermostPostDto(
              id: 'old',
              rootId: 'root',
              userId: 'other',
              channelId: 'channel',
              message: '@me old',
              createAt: 900,
            ),
            MattermostPostDto(
              id: 'personal',
              rootId: 'root',
              userId: 'other',
              channelId: 'channel',
              message: '@me please review',
              createAt: 2000,
            ),
            MattermostPostDto(
              id: 'group',
              rootId: 'root',
              userId: 'other',
              channelId: 'channel',
              message: '@backend please review',
              createAt: 3000,
            ),
          ],
        },
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);

      final ThreadInboxItem item = snapshot.newItems.single as ThreadInboxItem;
      expect(item.thread.unreadReplies, 2);
      expect(item.unreadMentionDetails?.mentionsCurrentUser, isTrue);
      expect(item.unreadMentionDetails?.groupMentionHandles, <String>[
        '@backend',
      ]);
      expect(item.unreadMentionDetails?.unclassifiedCount, 0);
      expect(api.loadedThreadId, 'root');
      expect(api.loadedThreadFromCreateAt, 1000);
      expect(api.loadedThreadDirection, PostThreadDirection.down);
    },
  );

  test(
    'does not classify an ordinary direct-thread reply as a mention',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 'team', name: 'team', displayName: 'Team'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'dm',
            teamId: 'team',
            type: 'D',
            name: 'me__other',
            displayName: 'Other',
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'dm', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[],
        threads: const <MattermostUserThreadDto>[
          MattermostUserThreadDto(
            id: 'root',
            replyCount: 1,
            lastReplyAt: 2000,
            lastViewedAt: 1000,
            participants: <MattermostUserDto>[],
            post: MattermostPostDto(
              id: 'root',
              userId: 'other',
              channelId: 'dm',
              message: 'Root',
              createAt: 500,
            ),
            unreadReplies: 1,
            unreadMentions: 1,
          ),
        ],
        threadPosts: const <String, List<MattermostPostDto>>{
          'root': <MattermostPostDto>[
            MattermostPostDto(
              id: 'reply',
              rootId: 'root',
              userId: 'other',
              channelId: 'dm',
              message: 'No explicit mention here',
              createAt: 2000,
            ),
          ],
        },
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);

      final ThreadInboxItem item = snapshot.newItems.single as ThreadInboxItem;
      expect(item.thread.unreadMentions, 1);
      expect(item.unreadMentionDetails?.hasMentions, isFalse);
    },
  );

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
    'suppresses individually viewed roots only in ordinary channels',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'channel',
            teamId: 't',
            type: 'O',
            name: 'channel',
            displayName: 'Channel',
            totalMessageCountRoot: 2,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'channel',
            userId: 'me',
            mentionCountRoot: 1,
            notifyProps: MattermostChannelNotifyPropsDto(
              markUnread: 'all',
              desktop: 'all',
            ),
          ),
        ],
        unread: const <MattermostPostDto>[
          MattermostPostDto(
            id: 'viewed',
            userId: 'other',
            channelId: 'channel',
            message: '@me one',
            createAt: 1,
          ),
          MattermostPostDto(
            id: 'remaining',
            userId: 'other',
            channelId: 'channel',
            message: 'two',
            createAt: 2,
          ),
        ],
      );
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
        viewedChannelPosts: _ViewedChannelPosts(<String, Set<String>>{
          'channel': <String>{'viewed'},
        }),
        userGroupCache: _GroupCache(),
      );

      final InboxSnapshot snapshot = await repository.load(session: session);

      expect(snapshot.newItems.single.postIds, <String>['remaining']);
      expect(snapshot.hasIncompleteMentionReconstruction, isFalse);
    },
  );

  test('restores group mentions and caches current membership', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: const <MattermostChannelDto>[
        MattermostChannelDto(
          id: 'c',
          teamId: 't',
          type: 'O',
          name: 'c',
          displayName: 'C',
          totalMessageCountRoot: 1,
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'c',
          userId: 'me',
          mentionCountRoot: 1,
        ),
      ],
      unread: const <MattermostPostDto>[
        MattermostPostDto(
          id: 'group-post',
          userId: 'other',
          channelId: 'c',
          message: 'hello @backend',
          createAt: 1,
        ),
      ],
      groups: const <MattermostGroupDto>[
        MattermostGroupDto(
          id: 'group-1',
          name: 'backend',
          displayName: 'Backend',
          allowReference: true,
        ),
      ],
    );
    final _GroupCache cache = _GroupCache();
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: const _Postponed(),
      userGroupCache: cache,
      now: () => DateTime.utc(2026, 9, 28),
    );

    final InboxSnapshot snapshot = await repository.load(session: session);

    final ChannelPostInboxItem item =
        snapshot.newItems.single as ChannelPostInboxItem;
    expect(item.candidate.reason, InboxAttentionReason.groupMention);
    expect(snapshot.hasIncompleteMentionReconstruction, isFalse);
    expect(cache.accountId, session.durableDataScopeId);
    expect(cache.groups.single.name, 'backend');
  });

  test('uses a fresh group membership cache when the endpoint fails', () async {
    final DateTime now = DateTime.utc(2026, 9, 28);
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: const <MattermostChannelDto>[
        MattermostChannelDto(
          id: 'c',
          teamId: 't',
          type: 'O',
          name: 'c',
          displayName: 'C',
          totalMessageCountRoot: 1,
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'c',
          userId: 'me',
          mentionCountRoot: 1,
        ),
      ],
      unread: const <MattermostPostDto>[
        MattermostPostDto(
          id: 'cached-group-post',
          userId: 'other',
          channelId: 'c',
          message: 'hello @backend',
          createAt: 1,
        ),
      ],
      groupLookupError: StateError('groups unavailable'),
    );
    final _GroupCache cache = _GroupCache(<CachedUserGroup>[
      CachedUserGroup(
        groupId: 'group-1',
        name: 'backend',
        displayName: 'Backend',
        allowReference: true,
        deleteAt: 0,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
    ]);
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: const _Postponed(),
      userGroupCache: cache,
      now: () => now,
    );

    final InboxSnapshot snapshot = await repository.load(session: session);

    final ChannelPostInboxItem item =
        snapshot.newItems.single as ChannelPostInboxItem;
    expect(item.candidate.reason, InboxAttentionReason.groupMention);
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

  test(
    'tracks an individual channel root without viewing its channel',
    () async {
      final _InboxApi api = _emptyApi();
      final _ViewedChannelPosts viewed = _ViewedChannelPosts(
        <String, Set<String>>{},
      );
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
        viewedChannelPosts: viewed,
        userGroupCache: _GroupCache(),
      );
      final ChannelPostInboxItem item = ChannelPostInboxItem(
        candidate: _candidate('post'),
      );

      await repository.markPostViewed(session: session, item: item);

      expect(api.viewedChannelId, isNull);
      expect(viewed.values['channel'], <String>{'post'});

      await repository.markRead(session: session, item: item);

      expect(api.viewedChannelId, 'channel');
      expect(viewed.values, isNot(contains('channel')));
    },
  );

  test(
    'retries stale viewed-post cleanup after channel view succeeds',
    () async {
      final _InboxApi api = _emptyApi();
      final _ViewedChannelPosts viewed = _ViewedChannelPosts(
        <String, Set<String>>{
          'channel': <String>{'post'},
        },
      )..failRemove = true;
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
        viewedChannelPosts: viewed,
        userGroupCache: _GroupCache(),
      );
      final ChannelPostInboxItem item = ChannelPostInboxItem(
        candidate: _candidate('post'),
      );

      await repository.markRead(session: session, item: item);

      expect(api.viewedChannelId, 'channel');
      expect(viewed.removeCalls, 1);
      expect(viewed.values, contains('channel'));

      viewed.failRemove = false;
      await repository.load(session: session);

      expect(viewed.removeCalls, 2);
      expect(viewed.values, isNot(contains('channel')));
    },
  );

  test('cleans a stale viewed-post preference after restart', () async {
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
          totalMessageCountRoot: 1,
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'channel',
          userId: 'me',
          msgCountRoot: 1,
        ),
      ],
      unread: const <MattermostPostDto>[],
    );
    final _ViewedChannelPosts viewed = _ViewedChannelPosts(
      <String, Set<String>>{
        'channel': <String>{'old-post'},
      },
    );
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: const _Postponed(),
      viewedChannelPosts: viewed,
      userGroupCache: _GroupCache(),
    );

    await repository.load(session: session);

    expect(viewed.removeCalls, 1);
    expect(viewed.values, isNot(contains('channel')));
  });

  test('marks a thread and its final root read at the current time', () async {
    final _InboxApi api = _emptyApi();
    final DateTime now = DateTime.utc(2026, 9, 4, 12);
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: const _Postponed(),
      userGroupCache: _GroupCache(),
      now: () => now,
    );
    final ThreadInboxItem item = ThreadInboxItem(
      thread: _thread(),
      channel: _channel(),
      teamId: 'source-team',
    );

    await repository.markThreadRead(
      session: session,
      item: item,
      preserveOtherChannelRoots: false,
    );

    expect(api.readThreadId, 'root');
    expect(api.readTeamId, 'source-team');
    expect(api.readTimestamp, now.millisecondsSinceEpoch);
    expect(api.viewedChannelId, 'channel');
  });

  test('marks a thread root selectively when other roots remain', () async {
    final _InboxApi api = _emptyApi();
    final _ViewedChannelPosts viewed = _ViewedChannelPosts(
      <String, Set<String>>{},
    );
    final MattermostInboxRepository repository = MattermostInboxRepository(
      api: api,
      messageMapper: const MattermostMessageMapper(),
      postponed: const _Postponed(),
      viewedChannelPosts: viewed,
      userGroupCache: _GroupCache(),
    );
    final ThreadInboxItem item = ThreadInboxItem(
      thread: _thread(),
      channel: _channel(),
      teamId: 'source-team',
    );

    await repository.markThreadRead(
      session: session,
      item: item,
      preserveOtherChannelRoots: true,
    );

    expect(api.readThreadId, 'root');
    expect(api.viewedChannelId, isNull);
    expect(viewed.values['channel'], <String>{'root'});
  });

  test(
    'uses server recipients to map username and group realtime mentions',
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
        groups: const <MattermostGroupDto>[
          MattermostGroupDto(
            id: 'group-1',
            name: 'backend',
            displayName: 'Backend',
            allowReference: true,
          ),
        ],
      );
      final _Gateway gateway = _Gateway();
      final SessionRealtimeService realtime = SessionRealtimeService(
        gateway: gateway,
        credentialStore: _Credentials(session.serverUrl),
      );
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
        userGroupCache: _GroupCache(),
        realtime: realtime,
      );
      await repository.load(session: session);
      final List<InboxRealtimeEvent> events = <InboxRealtimeEvent>[];
      final StreamSubscription<InboxRealtimeEvent> subscription = repository
          .watch(session: session)
          .listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await realtime.dispose();
        await gateway.close();
      });
      await _waitUntil(() => gateway.started);

      expect(gateway.acceptsEvent?.call('posted'), isTrue);
      // The session fan-out observes every event/sequence and filters for each
      // repository subscriber above the transport.
      expect(gateway.acceptsEvent?.call('typing'), isTrue);
      expect(gateway.acceptsChannel?.call('channel'), isTrue);
      expect(gateway.acceptsChannel?.call('unrelated'), isTrue);

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
              'mentions': jsonEncode(<String>['me']),
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
              'mentions': jsonEncode(<String>[]),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      await _waitUntil(() => events.whereType<InboxPostChanged>().length == 2);
      expect(events.whereType<InboxPostChanged>().last.candidate, isNull);

      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 3,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'group-mention',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'hello @backend',
                'create_at': 3,
              }),
              'mentions': jsonEncode(<String>['me']),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      await _waitUntil(() => events.whereType<InboxPostChanged>().length == 3);
      expect(
        events.whereType<InboxPostChanged>().last.candidate?.reason,
        InboxAttentionReason.groupMention,
      );
      expect(
        events.whereType<InboxPostChanged>().last.candidate?.groupMentionHandle,
        '@backend',
      );

      final ChannelPostInboxItem locallyViewed = ChannelPostInboxItem(
        candidate: _candidate('locally-viewed'),
      );
      await repository.markPostViewed(session: session, item: locallyViewed);
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'post_edited',
            sequence: 4,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'locally-viewed',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'edited @me',
                'create_at': 4,
              }),
              'mentions': jsonEncode(<String>['me']),
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
      await _waitUntil(() => events.whereType<InboxPostChanged>().length == 4);
      expect(events.whereType<InboxPostChanged>().last.candidate, isNull);

      gateway.add(
        const WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'group_member_delete',
            sequence: 5,
            data: <String, Object?>{},
            broadcast: <String, Object?>{'user_id': 'me'},
          ),
        ),
      );
      await _waitUntil(
        () => events.whereType<InboxRefreshRequired>().isNotEmpty,
      );
    },
  );

  test(
    'refreshes thread projections and recovers after connection gaps',
    () async {
      final _Gateway gateway = _Gateway();
      final SessionRealtimeService realtime = SessionRealtimeService(
        gateway: gateway,
        credentialStore: _Credentials(session.serverUrl),
      );
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
        userGroupCache: _GroupCache(),
        realtime: realtime,
      );
      await repository.load(session: session);
      final List<InboxRealtimeEvent> events = <InboxRealtimeEvent>[];
      final StreamSubscription<InboxRealtimeEvent> subscription = repository
          .watch(session: session)
          .listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await realtime.dispose();
        await gateway.close();
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
      var sequence = 2;
      for (final String name in <String>[
        'thread_updated',
        'thread_follow_changed',
        'thread_read_changed',
        'preference_changed',
      ]) {
        gateway.add(
          WebSocketEventSignal(
            MattermostWebSocketEvent(
              name: name,
              sequence: sequence++,
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
            sequence: sequence++,
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

      await _waitUntil(
        () => events.whereType<InboxRefreshRequired>().length == 3,
      );

      gateway.add(
        const WebSocketConnectionSignal(
          status: WebSocketConnectionStatus.connected,
          isReconnect: true,
        ),
      );
      await _waitUntil(
        () => events.whereType<InboxRefreshRequired>().length == 4,
      );
      gateway.add(
        WebSocketSequenceGapSignal(expected: sequence, actual: sequence + 1),
      );
      await _waitUntil(
        () => events.whereType<InboxRefreshRequired>().length == 5,
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
  userGroupCache: _GroupCache(),
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
    this.groups = const <MattermostGroupDto>[],
    this.threads = const <MattermostUserThreadDto>[],
    this.threadPages,
    this.threadPosts = const <String, List<MattermostPostDto>>{},
    this.groupLookupError,
    this.failUserLookup = false,
  });
  final List<MattermostTeamDto> teams;
  final List<MattermostChannelDto> channels;
  final List<MattermostChannelMemberDto> members;
  final List<MattermostPostDto> unread;
  final List<MattermostUserDto> users;
  final MattermostGroupChannelUsersDto groupUsers;
  final List<MattermostGroupDto> groups;
  final List<MattermostUserThreadDto> threads;
  final List<List<MattermostUserThreadDto>>? threadPages;
  final List<String?> requestedThreadCursors = <String?>[];
  final List<bool> requestedUnreadFilters = <bool>[];
  final Map<String, List<MattermostPostDto>> threadPosts;
  final Object? groupLookupError;
  final bool failUserLookup;
  final List<String> unreadChannelIds = <String>[];
  String? viewedChannelId;
  String? viewedUserId;
  String? readThreadId;
  String? readTeamId;
  int? readTimestamp;
  String? loadedThreadId;
  int? loadedThreadFromCreateAt;
  PostThreadDirection? loadedThreadDirection;
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
    String? before,
    int perPage = 60,
    bool extended = true,
    bool unread = false,
  }) async {
    requestedThreadCursors.add(before);
    requestedUnreadFilters.add(unread);
    final List<MattermostUserThreadDto> available = <MattermostUserThreadDto>[
      ...?threadPages?.expand((page) => page),
      if (threadPages == null) ...threads,
    ];
    final List<MattermostUserThreadDto> filtered = unread
        ? available.where((thread) => thread.unreadReplies > 0).toList()
        : available;
    final int offset = before == null
        ? 0
        : filtered.indexWhere((thread) => thread.id == before) + 1;
    final List<MattermostUserThreadDto> selected = filtered
        .skip(offset)
        .take(perPage)
        .toList();
    return MattermostUserThreadsDto(
      total: filtered.length,
      totalUnreadThreads: available
          .where((thread) => thread.unreadReplies > 0)
          .length,
      totalUnreadMentions: threads.fold<int>(
        0,
        (int count, MattermostUserThreadDto thread) =>
            count + thread.unreadMentions,
      ),
      threads: selected,
    );
  }

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) async {
    loadedThreadId = rootPostId;
    loadedThreadFromCreateAt = fromCreateAt;
    loadedThreadDirection = direction;
    final List<MattermostPostDto> posts =
        threadPosts[rootPostId] ?? const <MattermostPostDto>[];
    return MattermostPostListDto(
      order: posts.map((MattermostPostDto post) => post.id).toList(),
      posts: <String, MattermostPostDto>{
        for (final MattermostPostDto post in posts) post.id: post,
      },
      nextPostId: '',
      previousPostId: '',
      hasNext: false,
    );
  }

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
  Future<List<MattermostGroupDto>> getGroupsForUser(String userId) async {
    final Object? error = groupLookupError;
    if (error != null) throw error;
    return groups;
  }

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

final class _ViewedChannelPosts extends ViewedChannelPostsRepository {
  _ViewedChannelPosts(this.values);

  final Map<String, Set<String>> values;
  var failRemove = false;
  var removeCalls = 0;

  @override
  Future<ViewedChannelPostsSnapshot> load({
    required AuthSession session,
  }) async => ViewedChannelPostsSnapshot(values);

  @override
  Future<void> add({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async {
    values.putIfAbsent(channelId, () => <String>{}).add(postId);
  }

  @override
  Future<void> removeChannel({
    required AuthSession session,
    required String channelId,
  }) async {
    removeCalls++;
    if (failRemove) throw StateError('preference delete failed');
    values.remove(channelId);
  }
}

final class _GroupCache implements UserGroupMembershipCache {
  _GroupCache([this.groups = const <CachedUserGroup>[]]);

  List<CachedUserGroup> groups;
  String? accountId;

  @override
  Future<List<CachedUserGroup>> getFresh({
    required String accountId,
    required DateTime now,
  }) async => groups
      .where((CachedUserGroup group) => group.expiresAt.isAfter(now))
      .toList(growable: false);

  @override
  Future<void> replaceAll({
    required String accountId,
    required List<CachedUserGroup> groups,
  }) async {
    this.accountId = accountId;
    this.groups = List<CachedUserGroup>.of(groups);
  }
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
