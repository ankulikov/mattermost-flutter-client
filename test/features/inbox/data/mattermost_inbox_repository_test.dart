import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
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
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/inbox_settings_repository.dart';
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

  test('merges distinct direct scopes returned by separate teams', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't1', name: 'one', displayName: 'One'),
        MattermostTeamDto(id: 't2', name: 'two', displayName: 'Two'),
      ],
      channels: const <MattermostChannelDto>[],
      members: const <MattermostChannelMemberDto>[],
      channelsByTeam: const <String, List<MattermostChannelDto>>{
        't1': <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'dm-one',
            teamId: 't1',
            type: 'D',
            name: 'me__ada',
            displayName: 'Ada',
            totalMessageCount: 1,
          ),
        ],
        't2': <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'dm-two',
            teamId: 't2',
            type: 'D',
            name: 'me__grace',
            displayName: 'Grace',
            totalMessageCount: 1,
          ),
        ],
      },
      membersByTeam: const <String, List<MattermostChannelMemberDto>>{
        't1': <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'dm-one', userId: 'me'),
        ],
        't2': <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'dm-two', userId: 'me'),
        ],
      },
      unread: const <MattermostPostDto>[
        MattermostPostDto(
          id: 'one',
          userId: 'ada',
          channelId: 'dm-one',
          message: 'One',
          createAt: 1,
        ),
        MattermostPostDto(
          id: 'two',
          userId: 'grace',
          channelId: 'dm-two',
          message: 'Two',
          createAt: 2,
        ),
      ],
      users: const <MattermostUserDto>[
        MattermostUserDto(id: 'ada', username: 'ada'),
        MattermostUserDto(id: 'grace', username: 'grace'),
      ],
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(api.channelRequestTeamIds, unorderedEquals(<String>['t1', 't2']));
    expect(api.memberRequestTeamIds, unorderedEquals(<String>['t1', 't2']));
    expect(
      snapshot.newItems.expand((InboxItem item) => item.postIds),
      unorderedEquals(<String>['one', 'two']),
    );
  });

  test(
    'bounds post hydration and author lookups to 100 IDs per request',
    () async {
      final List<PostponedReference> references =
          List<PostponedReference>.generate(
            101,
            (int index) => PostponedReference(
              postId: 'post-$index',
              kind: PostponedReferenceKind.post,
              addedAt: DateTime.utc(2026, 9, 27),
            ),
          );
      final List<MattermostPostDto> postponedPosts =
          List<MattermostPostDto>.generate(
            101,
            (int index) => MattermostPostDto(
              id: 'post-$index',
              userId: 'author-$index',
              channelId: 'dm',
              message: 'Post $index',
              createAt: index + 1,
            ),
          );
      final List<MattermostUserDto> authors = List<MattermostUserDto>.generate(
        101,
        (int index) =>
            MattermostUserDto(id: 'author-$index', username: 'author-$index'),
      );
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 'team', displayName: 'Team'),
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
        unread: postponedPosts,
        users: authors,
      );

      final InboxSnapshot snapshot = await _repository(
        api,
        _Postponed(references),
      ).load(session: session);

      expect(
        api.postHydrationRequests.map((List<String> ids) => ids.length),
        <int>[100, 1],
      );
      final List<int> authorBatchSizes = api.userLookupRequests
          .map((List<String> ids) => ids.length)
          .toList(growable: false);
      final int authorBatchStart = authorBatchSizes.indexOf(100);
      expect(authorBatchSizes.every((int size) => size <= 100), isTrue);
      expect(authorBatchStart, greaterThanOrEqualTo(0));
      expect(authorBatchSizes.sublist(authorBatchStart), <int>[100, 1]);
      expect(snapshot.postponedMessageCount, 101);
    },
  );

  test(
    'applies the server-backed direct grouping mode to the snapshot',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't1', name: 'one', displayName: 'One'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'dm',
            teamId: 't1',
            type: 'D',
            name: 'dm',
            displayName: 'DM',
            totalMessageCount: 3,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'dm',
            userId: 'me',
            msgCount: 1,
          ),
        ],
        unread: const <MattermostPostDto>[
          MattermostPostDto(
            id: 'p1',
            userId: 'other',
            channelId: 'dm',
            message: 'first',
            createAt: 2,
          ),
          MattermostPostDto(
            id: 'p2',
            userId: 'other',
            channelId: 'dm',
            message: 'second',
            createAt: 3,
          ),
        ],
      );
      final _StaticInboxSettings settings = _StaticInboxSettings(
        const InboxSettings(
          directGrouping: InboxDirectGroupingSettings(
            mode: InboxDirectGroupingMode.none,
          ),
        ),
      );

      final InboxSnapshot snapshot = await _repository(
        api,
        null,
        settings,
      ).load(session: session);

      expect(settings.loads, 1);
      expect(snapshot.newItems, hasLength(2));
      expect(
        snapshot.newItems.map((InboxItem item) => item.postIds.single),
        containsAll(<String>['p1', 'p2']),
      );
    },
  );

  test('loads the shared Inbox context once before running sources', () async {
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't1', name: 'one', displayName: 'One'),
        MattermostTeamDto(id: 't2', name: 'two', displayName: 'Two'),
      ],
      channels: const <MattermostChannelDto>[],
      members: const <MattermostChannelMemberDto>[],
      unread: const <MattermostPostDto>[],
    );

    await _repository(api).load(session: session);

    expect(api.currentUserRequests, 1);
    expect(api.teamsRequests, 1);
    expect(api.channelRequestTeamIds, unorderedEquals(<String>['t1', 't2']));
    expect(api.memberRequestTeamIds, unorderedEquals(<String>['t1', 't2']));
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
              UnavailablePostponedInboxItem() => throw StateError(
                'The fixture does not contain unavailable postponed items.',
              ),
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

  test(
    'keeps an unavailable postponed reference as a safe queue placeholder',
    () async {
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
          MattermostChannelMemberDto(channelId: 'c', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[
          MattermostPostDto(
            id: 'p1',
            userId: 'other',
            channelId: 'c',
            message: 'content must not reach the placeholder',
            createAt: 1,
          ),
        ],
        failPostHydration: true,
      );
      final PostponedReference postReference = PostponedReference(
        postId: 'p1',
        kind: PostponedReferenceKind.post,
        addedAt: DateTime.utc(2026, 9, 1),
        targetPostId: 'reply-id',
      );
      final PostponedReference threadReference = PostponedReference(
        postId: 'missing-thread-root',
        kind: PostponedReferenceKind.thread,
        addedAt: DateTime.utc(2026, 9, 2),
      );

      final InboxSnapshot snapshot = await _repository(
        api,
        _Postponed(<PostponedReference>[postReference, threadReference]),
      ).load(session: session);

      expect(snapshot.newItems, isEmpty);
      expect(snapshot.postponedItems, hasLength(2));
      final List<UnavailablePostponedInboxItem> items = snapshot.postponedItems
          .whereType<UnavailablePostponedInboxItem>()
          .toList(growable: false);
      expect(items, hasLength(2));
      expect(
        items.map((item) => item.reference),
        containsAll(<Object>[same(postReference), same(threadReference)]),
      );
      expect(
        items
            .singleWhere(
              (UnavailablePostponedInboxItem item) =>
                  item.reference.kind == PostponedReferenceKind.post,
            )
            .postIds,
        <String>['p1'],
      );
      expect(
        items
            .singleWhere(
              (UnavailablePostponedInboxItem item) =>
                  item.reference.kind == PostponedReferenceKind.thread,
            )
            .threadRootIds,
        <String>{'missing-thread-root'},
      );
      expect(
        snapshot.diagnosticsCodes,
        contains(InboxSourceDiagnosticCode.postponedHydrationUnavailable),
      );
    },
  );

  test('keeps a postponed reference when hydration returns no post', () async {
    final PostponedReference reference = PostponedReference(
      postId: 'no-longer-accessible',
      kind: PostponedReferenceKind.post,
      addedAt: DateTime.utc(2026, 9, 3),
    );

    final InboxSnapshot snapshot = await _repository(
      _emptyApi(),
      _Postponed(<PostponedReference>[reference]),
    ).load(session: session);

    expect(snapshot.postponedItems, hasLength(1));
    expect(
      snapshot.postponedItems.single,
      isA<UnavailablePostponedInboxItem>().having(
        (UnavailablePostponedInboxItem item) => item.reference,
        'reference',
        same(reference),
      ),
    );
    expect(
      snapshot.diagnosticsCodes,
      contains(InboxSourceDiagnosticCode.postponedHydrationUnavailable),
    );
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
    'reconstructs username, first-name, keyword, and channel mentions',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'username',
            teamId: 't',
            type: 'O',
            name: 'username',
            displayName: 'Username',
            totalMessageCountRoot: 1,
          ),
          MattermostChannelDto(
            id: 'first-name',
            teamId: 't',
            type: 'O',
            name: 'first-name',
            displayName: 'First name',
            totalMessageCountRoot: 1,
          ),
          MattermostChannelDto(
            id: 'keyword',
            teamId: 't',
            type: 'O',
            name: 'keyword',
            displayName: 'Keyword',
            totalMessageCountRoot: 1,
          ),
          MattermostChannelDto(
            id: 'channel-wide',
            teamId: 't',
            type: 'O',
            name: 'channel-wide',
            displayName: 'Channel-wide',
            totalMessageCountRoot: 1,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'username',
            userId: 'me',
            mentionCountRoot: 1,
          ),
          MattermostChannelMemberDto(
            channelId: 'first-name',
            userId: 'me',
            mentionCountRoot: 1,
          ),
          MattermostChannelMemberDto(
            channelId: 'keyword',
            userId: 'me',
            mentionCountRoot: 1,
          ),
          MattermostChannelMemberDto(
            channelId: 'channel-wide',
            userId: 'me',
            mentionCountRoot: 1,
          ),
        ],
        unread: const <MattermostPostDto>[
          MattermostPostDto(
            id: 'username-post',
            userId: 'other',
            channelId: 'username',
            message: 'Hello @ME',
            createAt: 1,
          ),
          MattermostPostDto(
            id: 'first-name-post',
            userId: 'other',
            channelId: 'first-name',
            message: 'Please review this, ADA.',
            createAt: 2,
          ),
          MattermostPostDto(
            id: 'keyword-post',
            userId: 'other',
            channelId: 'keyword',
            message: 'This is URGENT.',
            createAt: 3,
          ),
          MattermostPostDto(
            id: 'channel-post',
            userId: 'other',
            channelId: 'channel-wide',
            message: 'Hello @CHANNEL',
            createAt: 4,
          ),
        ],
        currentUser: const MattermostUserDto(
          id: 'me',
          username: 'me',
          firstName: 'Ada',
          notifyProps: UserNotifyPropsDto(
            desktop: 'mention',
            firstName: 'true',
            mentionKeys: 'urgent',
            channel: 'true',
          ),
        ),
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);
      final Map<String, InboxAttentionReason> reasons =
          <String, InboxAttentionReason>{
            for (final ChannelPostInboxItem item
                in snapshot.newItems.whereType<ChannelPostInboxItem>())
              item.post.id: item.candidate.reason,
          };

      expect(snapshot.completeness, InboxCompleteness.exact);
      expect(reasons, <String, InboxAttentionReason>{
        'username-post': InboxAttentionReason.directMention,
        'first-name-post': InboxAttentionReason.directMention,
        'keyword-post': InboxAttentionReason.keywordMention,
        'channel-post': InboxAttentionReason.channelMention,
      });
    },
  );

  test('does not treat @here as an exact historical mention', () async {
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
          id: 'here',
          userId: 'other',
          channelId: 'c',
          message: 'Attention @here',
          createAt: 1,
        ),
      ],
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(snapshot.newItems, isEmpty);
    expect(snapshot.completeness, InboxCompleteness.approximateMentions);
    expect(
      snapshot.diagnosticsCodes,
      contains(InboxSourceDiagnosticCode.mentionReconstructionMismatch),
    );
  });

  test(
    'does not treat a group mention as an exact historical mention',
    () async {
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
            id: 'group',
            userId: 'other',
            channelId: 'c',
            message: 'Attention @engineering',
            createAt: 1,
          ),
        ],
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);

      expect(snapshot.newItems, isEmpty);
      expect(snapshot.completeness, InboxCompleteness.approximateMentions);
      expect(
        snapshot.diagnosticsCodes,
        contains(InboxSourceDiagnosticCode.mentionReconstructionMismatch),
      );
    },
  );

  test('continues unread ranges toward the membership counter', () async {
    const MattermostChannelDto channel = MattermostChannelDto(
      id: 'c',
      teamId: 't',
      type: 'O',
      name: 'c',
      displayName: 'C',
      totalMessageCountRoot: 3,
    );
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: const <MattermostChannelDto>[channel],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'c',
          userId: 'me',
          mentionCountRoot: 3,
        ),
      ],
      unread: const <MattermostPostDto>[],
      unreadPages: <String, MattermostPostListDto>{
        'c': _postList(<MattermostPostDto>[
          _unreadPost(id: 'newest', channelId: 'c', createAt: 2),
          _unreadPost(id: 'oldest', channelId: 'c', createAt: 1),
        ]),
      },
      afterPages: <String, MattermostPostListDto>{
        'c|newest': _postList(<MattermostPostDto>[
          _unreadPost(id: 'latest', channelId: 'c', createAt: 3),
        ]),
      },
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(api.afterRequests, <String>['c|newest']);
    expect(snapshot.completeness, InboxCompleteness.exact);
    expect(
      snapshot.newItems.expand((InboxItem item) => item.postIds),
      unorderedEquals(<String>['latest', 'newest', 'oldest']),
    );
  });

  test('reports a cursor loop as a truncated unread range', () async {
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
          totalMessageCountRoot: 2,
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'c',
          userId: 'me',
          mentionCountRoot: 2,
        ),
      ],
      unread: const <MattermostPostDto>[],
      unreadPages: <String, MattermostPostListDto>{
        'c': _postList(<MattermostPostDto>[
          _unreadPost(id: 'repeated', channelId: 'c', createAt: 1),
        ]),
      },
      afterPages: <String, MattermostPostListDto>{
        'c|repeated': _postList(<MattermostPostDto>[
          _unreadPost(id: 'repeated', channelId: 'c', createAt: 1),
        ]),
      },
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(snapshot.completeness, InboxCompleteness.truncated);
    expect(
      snapshot.diagnosticsCodes,
      contains(InboxSourceDiagnosticCode.unreadRangeCursorLoopDetected),
    );
  });

  test(
    'reports the unread range safety cap without silently completing',
    () async {
      final Map<String, MattermostPostListDto> afterPages =
          <String, MattermostPostListDto>{};
      for (var index = 1; index < 8; index++) {
        afterPages['c|p$index'] = _postList(<MattermostPostDto>[
          _unreadPost(id: 'p${index + 1}', channelId: 'c', createAt: index + 1),
        ]);
      }
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
            totalMessageCountRoot: 9,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'c',
            userId: 'me',
            mentionCountRoot: 9,
          ),
        ],
        unread: const <MattermostPostDto>[],
        unreadPages: <String, MattermostPostListDto>{
          'c': _postList(<MattermostPostDto>[
            _unreadPost(id: 'p1', channelId: 'c', createAt: 1),
          ]),
        },
        afterPages: afterPages,
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);

      expect(api.afterRequests, hasLength(7));
      expect(snapshot.completeness, InboxCompleteness.truncated);
      expect(
        snapshot.diagnosticsCodes,
        contains(InboxSourceDiagnosticCode.unreadRangeSafetyCapReached),
      );
    },
  );

  test('limits concurrent unread range requests to four channels', () async {
    final Completer<void> firstWaveStarted = Completer<void>();
    final Completer<void> releaseRequests = Completer<void>();
    var activeRequests = 0;
    var maxActiveRequests = 0;
    final List<MattermostChannelDto> channels =
        List<MattermostChannelDto>.generate(
          5,
          (int index) => MattermostChannelDto(
            id: 'c$index',
            teamId: 't',
            type: 'O',
            name: 'c$index',
            displayName: 'C$index',
            totalMessageCountRoot: 1,
          ),
        );
    final List<MattermostChannelMemberDto> members =
        List<MattermostChannelMemberDto>.generate(
          5,
          (int index) => MattermostChannelMemberDto(
            channelId: 'c$index',
            userId: 'me',
            mentionCountRoot: 1,
          ),
        );
    final _InboxApi api = _InboxApi(
      teams: const <MattermostTeamDto>[
        MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
      ],
      channels: channels,
      members: members,
      unread: const <MattermostPostDto>[],
      onUnreadRequest: () async {
        activeRequests++;
        maxActiveRequests = maxActiveRequests < activeRequests
            ? activeRequests
            : maxActiveRequests;
        if (activeRequests == 4 && !firstWaveStarted.isCompleted) {
          firstWaveStarted.complete();
        }
        await releaseRequests.future;
        activeRequests--;
      },
    );

    final Future<InboxSnapshot> load = _repository(api).load(session: session);
    await firstWaveStarted.future;

    expect(maxActiveRequests, 4);
    expect(activeRequests, 4);
    releaseRequests.complete();
    await load;
    expect(maxActiveRequests, 4);
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

  test('desktop none excludes channel, DM, and GM unread sources', () async {
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
        MattermostChannelDto(
          id: 'direct',
          teamId: 't',
          type: 'D',
          name: 'me__other',
          displayName: 'Direct',
          totalMessageCount: 2,
        ),
        MattermostChannelDto(
          id: 'group',
          teamId: 't',
          type: 'G',
          name: 'group',
          displayName: 'Group',
          totalMessageCount: 2,
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(
          channelId: 'channel',
          userId: 'me',
          msgCountRoot: 1,
          mentionCountRoot: 1,
          notifyProps: MattermostChannelNotifyPropsDto(desktop: 'none'),
        ),
        MattermostChannelMemberDto(
          channelId: 'direct',
          userId: 'me',
          msgCount: 1,
          notifyProps: MattermostChannelNotifyPropsDto(desktop: 'none'),
        ),
        MattermostChannelMemberDto(
          channelId: 'group',
          userId: 'me',
          msgCount: 1,
          notifyProps: MattermostChannelNotifyPropsDto(desktop: 'none'),
        ),
      ],
      unread: const <MattermostPostDto>[],
      currentUser: const MattermostUserDto(
        id: 'me',
        username: 'me',
        notifyProps: UserNotifyPropsDto(desktop: 'all'),
      ),
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(snapshot.newItems, isEmpty);
    expect(api.unreadChannelIds, isEmpty);
  });

  test(
    'channel sources preserve effective desktop mention and all semantics',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'mention',
            teamId: 't',
            type: 'O',
            name: 'mention',
            displayName: 'Mention',
            totalMessageCountRoot: 1,
          ),
          MattermostChannelDto(
            id: 'all',
            teamId: 't',
            type: 'O',
            name: 'all',
            displayName: 'All',
            totalMessageCountRoot: 1,
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(
            channelId: 'mention',
            userId: 'me',
            mentionCountRoot: 1,
          ),
          MattermostChannelMemberDto(
            channelId: 'all',
            userId: 'me',
            notifyProps: MattermostChannelNotifyPropsDto(
              desktop: 'all',
              markUnread: 'all',
            ),
          ),
        ],
        unread: const <MattermostPostDto>[
          MattermostPostDto(
            id: 'mention-post',
            userId: 'other',
            channelId: 'mention',
            message: 'hello @me',
            createAt: 1,
          ),
          MattermostPostDto(
            id: 'all-post',
            userId: 'other',
            channelId: 'all',
            message: 'ordinary activity',
            createAt: 2,
          ),
        ],
        currentUser: const MattermostUserDto(
          id: 'me',
          username: 'me',
          notifyProps: UserNotifyPropsDto(desktop: 'mention'),
        ),
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);

      expect(
        snapshot.newItems.expand((InboxItem item) => item.postIds),
        unorderedEquals(<String>['mention-post', 'all-post']),
      );
    },
  );

  test(
    'followed threads respect desktop threads, hard channel none, and deleted roots',
    () async {
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 't', name: 't', displayName: 'T'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'included',
            teamId: 't',
            type: 'O',
            name: 'included',
            displayName: 'Included',
          ),
          MattermostChannelDto(
            id: 'none',
            teamId: 't',
            type: 'O',
            name: 'none',
            displayName: 'None',
          ),
          MattermostChannelDto(
            id: 'deleted',
            teamId: 't',
            type: 'O',
            name: 'deleted',
            displayName: 'Deleted',
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'included', userId: 'me'),
          MattermostChannelMemberDto(
            channelId: 'none',
            userId: 'me',
            notifyProps: MattermostChannelNotifyPropsDto(desktop: 'none'),
          ),
          MattermostChannelMemberDto(channelId: 'deleted', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[],
        threadsByTeam: <String, List<MattermostUserThreadDto>>{
          't': <MattermostUserThreadDto>[
            _userThread(rootId: 'included-root', channelId: 'included'),
            _userThread(rootId: 'none-root', channelId: 'none'),
            _userThread(
              rootId: 'deleted-root',
              channelId: 'deleted',
              deletedRoot: true,
            ),
          ],
        },
        currentUser: const MattermostUserDto(
          id: 'me',
          username: 'me',
          notifyProps: UserNotifyPropsDto(
            desktop: 'all',
            desktopThreads: 'all',
          ),
        ),
      );

      final InboxSnapshot snapshot = await _repository(
        api,
      ).load(session: session);

      expect(snapshot.newItems, hasLength(1));
      expect(snapshot.newItems.single, isA<ThreadInboxItem>());
      expect(snapshot.newItems.single.postIds, <String>['included-root']);
    },
  );

  test('mention-only followed threads require unread mentions', () async {
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
        ),
        MattermostChannelDto(
          id: 'mention',
          teamId: 't',
          type: 'O',
          name: 'mention',
          displayName: 'Mention',
        ),
      ],
      members: const <MattermostChannelMemberDto>[
        MattermostChannelMemberDto(channelId: 'ordinary', userId: 'me'),
        MattermostChannelMemberDto(channelId: 'mention', userId: 'me'),
      ],
      unread: const <MattermostPostDto>[],
      threadsByTeam: <String, List<MattermostUserThreadDto>>{
        't': <MattermostUserThreadDto>[
          _userThread(rootId: 'ordinary-root', channelId: 'ordinary'),
          _userThread(
            rootId: 'mention-root',
            channelId: 'mention',
            unreadReplies: 0,
            unreadMentions: 1,
          ),
        ],
      },
      currentUser: const MattermostUserDto(
        id: 'me',
        username: 'me',
        notifyProps: UserNotifyPropsDto(
          desktop: 'all',
          desktopThreads: 'mention',
        ),
      ),
    );

    final InboxSnapshot snapshot = await _repository(
      api,
    ).load(session: session);

    expect(snapshot.newItems, hasLength(1));
    expect(snapshot.newItems.single.postIds, <String>['mention-root']);
  });

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
      final SessionRealtimeService realtime = SessionRealtimeService(
        gateway: gateway,
        credentialStore: _Credentials(session.serverUrl),
      );
      final MattermostInboxRepository repository = MattermostInboxRepository(
        api: api,
        messageMapper: const MattermostMessageMapper(),
        postponed: const _Postponed(),
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
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<InboxPostChanged>(), hasLength(1));
    },
  );

  test('maps root creates for D/G/O/P with desktop eligibility', () async {
    for (final ({String type, String desktop, bool mention, bool expected})
        testCase
        in <({String type, String desktop, bool mention, bool expected})>[
          (type: 'D', desktop: 'all', mention: false, expected: true),
          (type: 'D', desktop: 'mention', mention: false, expected: true),
          (type: 'D', desktop: 'none', mention: false, expected: false),
          (type: 'G', desktop: 'all', mention: false, expected: true),
          (type: 'G', desktop: 'mention', mention: false, expected: true),
          (type: 'G', desktop: 'none', mention: false, expected: false),
          (type: 'O', desktop: 'all', mention: false, expected: true),
          (type: 'O', desktop: 'mention', mention: true, expected: true),
          (type: 'O', desktop: 'none', mention: true, expected: false),
          (type: 'P', desktop: 'all', mention: false, expected: true),
          (type: 'P', desktop: 'mention', mention: true, expected: true),
          (type: 'P', desktop: 'none', mention: true, expected: false),
        ]) {
      final _InboxApi api = _realtimeApi(
        channelType: testCase.type,
        desktop: testCase.desktop,
      );
      final _RealtimeHarness harness = await _startRealtime(
        api: api,
        session: session,
      );
      addTearDown(harness.dispose);

      harness.gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'post-${testCase.type}-${testCase.desktop}',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'ordinary content',
                'create_at': 1,
              }),
              if (testCase.mention) 'mentions': <String>['me'],
              'channel_type': testCase.type,
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );

      if (testCase.expected) {
        await _waitUntil(
          () => harness.events.whereType<InboxPostChanged>().isNotEmpty,
        );
        final InboxPostChanged change = harness.events
            .whereType<InboxPostChanged>()
            .single;
        expect(change.kind, InboxPostChangeKind.created);
        expect(
          change.candidate?.reason,
          testCase.mention
              ? InboxAttentionReason.directMention
              : InboxAttentionReason.allMessagesSubscription,
        );
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(harness.events.whereType<InboxPostChanged>(), isEmpty);
      }
    }
  });

  test('uses server mentions over text for a desktop mention root', () async {
    final _RealtimeHarness harness = await _startRealtime(
      api: _realtimeApi(channelType: 'O', desktop: 'mention'),
      session: session,
    );
    addTearDown(harness.dispose);

    harness.gateway.add(
      WebSocketEventSignal(
        MattermostWebSocketEvent(
          name: 'posted',
          sequence: 1,
          data: <String, Object?>{
            'post': jsonEncode(<String, Object?>{
              'id': 'text-only',
              'user_id': 'other',
              'channel_id': 'channel',
              'message': 'looks like @me',
              'create_at': 1,
            }),
            'mentions': const <String>[],
          },
          broadcast: const <String, Object?>{'channel_id': 'channel'},
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.events.whereType<InboxPostChanged>(), isEmpty);

    harness.gateway.add(
      WebSocketEventSignal(
        MattermostWebSocketEvent(
          name: 'posted',
          sequence: 2,
          data: <String, Object?>{
            'post': jsonEncode(<String, Object?>{
              'id': 'server-mention',
              'user_id': 'other',
              'channel_id': 'channel',
              'message': 'ordinary content',
              'create_at': 2,
            }),
            'mentions': const <String>['me'],
          },
          broadcast: const <String, Object?>{'channel_id': 'channel'},
        ),
      ),
    );
    await _waitUntil(
      () => harness.events.whereType<InboxPostChanged>().isNotEmpty,
    );
    expect(
      harness.events.whereType<InboxPostChanged>().single.candidate?.reason,
      InboxAttentionReason.directMention,
    );
  });

  test(
    'accepts the current user ID in server-provided realtime mentions',
    () async {
      final AuthSession idSession = AuthSession(
        serverUrl: Uri.parse('https://chat.example'),
        userId: 'user-id-not-username',
        username: 'me',
      );
      final _InboxApi api = _realtimeApi(channelType: 'O', desktop: 'mention');
      api.currentUser = const MattermostUserDto(
        id: 'user-id-not-username',
        username: 'me',
        notifyProps: UserNotifyPropsDto(desktop: 'mention'),
      );
      final _RealtimeHarness harness = await _startRealtime(
        api: api,
        session: idSession,
      );
      addTearDown(harness.dispose);

      harness.gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'server-id-mention',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'No local text match needed',
                'create_at': 1,
              }),
              'mentions': const <String>['user-id-not-username'],
            },
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );

      await _waitUntil(
        () => harness.events.whereType<InboxPostChanged>().isNotEmpty,
      );
      expect(
        harness.events.whereType<InboxPostChanged>().single.candidate?.reason,
        InboxAttentionReason.directMention,
      );
    },
  );

  test(
    'turns an oversized realtime post payload into bounded recovery',
    () async {
      final _RealtimeHarness harness = await _startRealtime(
        api: _realtimeApi(channelType: 'O', desktop: 'all'),
        session: session,
      );
      addTearDown(harness.dispose);

      harness.gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{'post': 'x' * (64 * 1024 + 1)},
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );

      await _waitUntil(
        () => harness.events.whereType<InboxRefreshRequired>().isNotEmpty,
      );
      expect(harness.events.whereType<InboxPostChanged>(), isEmpty);
    },
  );

  test(
    'maps unknown-channel root events to recovery rather than deletion',
    () async {
      final _RealtimeHarness harness = await _startRealtime(
        api: _realtimeApi(channelType: 'O', desktop: 'all'),
        session: session,
      );
      addTearDown(harness.dispose);

      harness.gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'unknown-channel-post',
                'user_id': 'other',
                'channel_id': 'unknown',
                'message': 'hello',
                'create_at': 1,
              }),
            },
            broadcast: const <String, Object?>{'channel_id': 'unknown'},
          ),
        ),
      );

      await _waitUntil(
        () => harness.events.whereType<InboxRefreshRequired>().isNotEmpty,
      );
      expect(harness.events.whereType<InboxPostChanged>(), isEmpty);
    },
  );

  test('maps post edits to typed preview-only deltas', () async {
    final _RealtimeHarness harness = await _startRealtime(
      api: _realtimeApi(channelType: 'O', desktop: 'all'),
      session: session,
    );
    addTearDown(harness.dispose);

    harness.gateway.add(
      WebSocketEventSignal(
        MattermostWebSocketEvent(
          name: 'post_edited',
          sequence: 1,
          data: <String, Object?>{
            'post': jsonEncode(<String, Object?>{
              'id': 'edited',
              'user_id': 'other',
              'channel_id': 'channel',
              'message': 'edited preview',
              'create_at': 1,
            }),
          },
          broadcast: const <String, Object?>{'channel_id': 'channel'},
        ),
      ),
    );

    await _waitUntil(
      () => harness.events.whereType<InboxPostChanged>().isNotEmpty,
    );
    final InboxPostChanged change = harness.events
        .whereType<InboxPostChanged>()
        .single;
    expect(change.kind, InboxPostChangeKind.edited);
    expect(change.candidate?.post.message, 'edited preview');
  });

  test('filters self, system, deleted, and silent root creates', () async {
    final _RealtimeHarness harness = await _startRealtime(
      api: _realtimeApi(channelType: 'O', desktop: 'all'),
      session: session,
    );
    addTearDown(harness.dispose);
    final List<Map<String, Object?>> posts = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'self',
        'user_id': 'me',
        'channel_id': 'channel',
        'message': 'self',
        'create_at': 1,
      },
      <String, Object?>{
        'id': 'system',
        'user_id': 'other',
        'channel_id': 'channel',
        'type': 'system_join_channel',
        'message': 'system',
        'create_at': 2,
      },
      <String, Object?>{
        'id': 'deleted',
        'user_id': 'other',
        'channel_id': 'channel',
        'delete_at': 1,
        'message': 'deleted',
        'create_at': 3,
      },
      <String, Object?>{
        'id': 'silent',
        'user_id': 'other',
        'channel_id': 'channel',
        'message': 'silent',
        'create_at': 4,
        'props': <String, Object?>{'silent_notification': true},
      },
    ];
    for (var index = 0; index < posts.length; index++) {
      harness.gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: index + 1,
            data: <String, Object?>{'post': jsonEncode(posts[index])},
            broadcast: const <String, Object?>{'channel_id': 'channel'},
          ),
        ),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.events.whereType<InboxPostChanged>(), isEmpty);
  });

  test(
    'buffers pre-scope transport events and decodes Inbox realtime payloads tolerantly',
    () async {
      final Completer<void> contextGate = Completer<void>();
      final _InboxApi api = _InboxApi(
        teams: const <MattermostTeamDto>[
          MattermostTeamDto(id: 'team', name: 'team', displayName: 'Team'),
        ],
        channels: const <MattermostChannelDto>[
          MattermostChannelDto(
            id: 'channel',
            teamId: 'team',
            name: 'channel',
            displayName: 'Channel',
            type: 'O',
          ),
        ],
        members: const <MattermostChannelMemberDto>[
          MattermostChannelMemberDto(channelId: 'channel', userId: 'me'),
        ],
        unread: const <MattermostPostDto>[],
        onCurrentUserRequest: () => contextGate.future,
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
        realtime: realtime,
      );
      final List<InboxRealtimeEvent> events = <InboxRealtimeEvent>[];
      final StreamSubscription<InboxRealtimeEvent> subscription = repository
          .watch(session: session)
          .listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        await realtime.dispose();
        await gateway.close();
      });
      final Future<InboxSnapshot> loading = repository.load(session: session);
      await _waitUntil(() => gateway.started && api.currentUserRequests == 1);

      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'posted',
            sequence: 1,
            data: <String, Object?>{
              'post': jsonEncode(<String, Object?>{
                'id': 'early-post',
                'user_id': 'other',
                'channel_id': 'channel',
                'message': 'hello @me',
                'create_at': 1,
              }),
              'mentions': '["me", 42]',
              'followers': <Object?>['me', '', 7],
              'channel_type': 'O',
            },
            broadcast: const <String, Object?>{},
          ),
        ),
      );
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'thread_updated',
            sequence: 2,
            data: <String, Object?>{
              'thread':
                  '{"id":"root","channel_id":"channel",'
                  '"unread_replies":"3","unread_mentions":1,'
                  '"is_following":"true"}',
            },
            broadcast: const <String, Object?>{},
          ),
        ),
      );
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'thread_follow_changed',
            sequence: 3,
            data: const <String, Object?>{
              'thread_id': 'root',
              'following': 'false',
            },
            broadcast: const <String, Object?>{},
          ),
        ),
      );
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'thread_read_changed',
            sequence: 4,
            data: const <String, Object?>{'post_id': 'root'},
            broadcast: const <String, Object?>{},
          ),
        ),
      );
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'preferences_changed',
            sequence: 5,
            data: const <String, Object?>{
              'preferences':
                  '[{"category":"notifications",'
                  '"name":"desktop","value":"all"},{}]',
            },
            broadcast: const <String, Object?>{},
          ),
        ),
      );
      gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'thread_updated',
            sequence: 6,
            data: const <String, Object?>{'thread': '{not json'},
            broadcast: const <String, Object?>{},
          ),
        ),
      );

      contextGate.complete();
      await loading;
      await _waitUntil(() => events.length == 5);

      final InboxPostChanged post = events.whereType<InboxPostChanged>().single;
      expect(post.sequence, 1);
      expect(post.mentions, <String>['me']);
      expect(post.followers, <String>['me']);
      expect(post.channelType, 'O');
      final InboxThreadUpdated updated = events
          .whereType<InboxThreadUpdated>()
          .single;
      expect(updated.rootPostId, 'root');
      expect(updated.unreadReplies, 3);
      expect(updated.unreadMentions, 1);
      expect(updated.isFollowing, isTrue);
      expect(
        events.whereType<InboxThreadFollowChanged>().single.isFollowing,
        isFalse,
      );
      expect(
        events.whereType<InboxThreadReadChanged>().single.rootPostId,
        'root',
      );
      expect(
        events.whereType<InboxEligibilityContextChanged>().single.kind,
        InboxEligibilityContextChangeKind.desktopNotifications,
      );
    },
  );

  test(
    'hydrates reply and aggregate thread deltas into one trusted thread',
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
        currentUser: const MattermostUserDto(
          id: 'me',
          username: 'me',
          notifyProps: UserNotifyPropsDto(desktopThreads: 'all'),
        ),
        threadById: <String, MattermostUserThreadDto>{
          'root': _userThread(
            rootId: 'root',
            channelId: 'channel',
            unreadReplies: 2,
          ),
        },
      );
      final _RealtimeHarness harness = await _startRealtime(
        api: api,
        session: session,
      );
      addTearDown(harness.dispose);

      harness.gateway.add(
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
                'message': 'Reply',
                'create_at': 2,
              }),
              'mentions': <String>['me'],
            },
            broadcast: const <String, Object?>{},
          ),
        ),
      );
      harness.gateway.add(
        WebSocketEventSignal(
          MattermostWebSocketEvent(
            name: 'thread_updated',
            sequence: 2,
            data: const <String, Object?>{
              'thread': <String, Object?>{
                'id': 'root',
                'channel_id': 'channel',
                'unread_replies': 2,
                'unread_mentions': 0,
                'is_following': true,
              },
            },
            broadcast: const <String, Object?>{},
          ),
        ),
      );

      await _waitUntil(
        () => harness.events.whereType<InboxThreadUpdated>().length == 2,
      );
      final List<InboxThreadUpdated> events = harness.events
          .whereType<InboxThreadUpdated>()
          .toList(growable: false);
      expect(
        events.map((InboxThreadUpdated event) => event.rootPostId),
        <String>['root', 'root'],
      );
      expect(
        events.every((InboxThreadUpdated event) => event.candidate != null),
        isTrue,
      );
      expect(events.first.candidate?.hasNewExplicitMention, isTrue);
      expect(events.last.candidate?.hasNewExplicitMention, isFalse);
      expect(api.threadRequests, 2);
    },
  );

  test(
    'requests HTTP recovery only after reconnect or a sequence gap',
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

  test(
    'maps only relevant eligibility context and postponed preferences',
    () async {
      final _RealtimeHarness harness = await _startRealtime(
        api: _realtimeApi(channelType: 'O', desktop: 'mention'),
        session: session,
      );
      addTearDown(harness.dispose);

      final List<MattermostWebSocketEvent> events = <MattermostWebSocketEvent>[
        const MattermostWebSocketEvent(
          name: 'preference_changed',
          sequence: 1,
          data: <String, Object?>{
            'category': 'notifications',
            'name': 'desktop',
            'value': 'all',
          },
          broadcast: <String, Object?>{},
        ),
        const MattermostWebSocketEvent(
          name: 'channel_member_updated',
          sequence: 2,
          data: <String, Object?>{
            'channel_member': <String, Object?>{
              'channel_id': 'channel',
              'user_id': 'me',
            },
          },
          broadcast: <String, Object?>{},
        ),
        const MattermostWebSocketEvent(
          name: 'direct_added',
          sequence: 3,
          data: <String, Object?>{'channel_id': 'new-direct'},
          broadcast: <String, Object?>{},
        ),
        const MattermostWebSocketEvent(
          name: 'group_added',
          sequence: 4,
          data: <String, Object?>{},
          broadcast: <String, Object?>{'channel_id': 'new-group'},
        ),
        const MattermostWebSocketEvent(
          name: 'user_updated',
          sequence: 5,
          data: <String, Object?>{
            'user': <String, Object?>{'id': 'me'},
          },
          broadcast: <String, Object?>{},
        ),
        MattermostWebSocketEvent(
          name: 'preferences_changed',
          sequence: 6,
          data: <String, Object?>{
            'preferences': jsonEncode(<Object?>[
              <String, Object?>{
                'category': 'postponed_messages',
                'name': 'postponed-id',
                'value': jsonEncode(<String, Object?>{
                  'post_id': 'postponed-id',
                  'kind': 'post',
                  'added_at': 1,
                }),
              },
            ]),
          },
          broadcast: const <String, Object?>{},
        ),
        const MattermostWebSocketEvent(
          name: 'preferences_changed',
          sequence: 7,
          data: <String, Object?>{
            'category': 'theme',
            'name': 'sidebar',
            'value': 'dark',
          },
          broadcast: <String, Object?>{},
        ),
        const MattermostWebSocketEvent(
          name: 'preference_changed',
          sequence: 8,
          data: <String, Object?>{
            'category': 'postponed_messages',
            'name': 'bad-id',
            'value': '{not json',
          },
          broadcast: <String, Object?>{},
        ),
      ];
      for (final MattermostWebSocketEvent event in events) {
        harness.gateway.add(WebSocketEventSignal(event));
      }

      await _waitUntil(() => harness.events.length == 6);
      final List<InboxEligibilityContextChanged> context = harness.events
          .whereType<InboxEligibilityContextChanged>()
          .toList(growable: false);
      expect(
        context.map((InboxEligibilityContextChanged event) => event.kind),
        <InboxEligibilityContextChangeKind>[
          InboxEligibilityContextChangeKind.desktopNotifications,
          InboxEligibilityContextChangeKind.channelMembership,
          InboxEligibilityContextChangeKind.directOrGroupAdded,
          InboxEligibilityContextChangeKind.directOrGroupAdded,
          InboxEligibilityContextChangeKind.currentUser,
        ],
      );
      final InboxRefreshRequired postponed = harness.events
          .whereType<InboxRefreshRequired>()
          .single;
      expect(postponed.scope, InboxRefreshScope.postponed);
    },
  );
}

_InboxApi _emptyApi() => _InboxApi(
  teams: const <MattermostTeamDto>[],
  channels: const <MattermostChannelDto>[],
  members: const <MattermostChannelMemberDto>[],
  unread: const <MattermostPostDto>[],
);

_InboxApi _realtimeApi({
  required String channelType,
  required String desktop,
}) => _InboxApi(
  teams: const <MattermostTeamDto>[
    MattermostTeamDto(id: 'team', name: 'team', displayName: 'Team'),
  ],
  channels: <MattermostChannelDto>[
    MattermostChannelDto(
      id: 'channel',
      teamId: 'team',
      type: channelType,
      name: channelType == 'D' ? 'me__other' : 'channel',
      displayName: 'Channel',
    ),
  ],
  members: <MattermostChannelMemberDto>[
    MattermostChannelMemberDto(
      channelId: 'channel',
      userId: 'me',
      notifyProps: const MattermostChannelNotifyPropsDto(markUnread: 'all'),
    ),
  ],
  unread: const <MattermostPostDto>[],
  currentUser: MattermostUserDto(
    id: 'me',
    username: 'me',
    notifyProps: UserNotifyPropsDto(desktop: desktop),
  ),
);

Future<_RealtimeHarness> _startRealtime({
  required _InboxApi api,
  required AuthSession session,
}) async {
  final _Gateway gateway = _Gateway();
  final SessionRealtimeService realtime = SessionRealtimeService(
    gateway: gateway,
    credentialStore: _Credentials(session.serverUrl),
  );
  final MattermostInboxRepository repository = MattermostInboxRepository(
    api: api,
    messageMapper: const MattermostMessageMapper(),
    postponed: const _Postponed(),
    realtime: realtime,
  );
  await repository.load(session: session);
  final List<InboxRealtimeEvent> events = <InboxRealtimeEvent>[];
  // The returned harness owns and cancels this subscription in [dispose].
  // ignore: cancel_subscriptions
  final StreamSubscription<InboxRealtimeEvent> subscription = repository
      .watch(session: session)
      .listen(events.add);
  await _waitUntil(() => gateway.started);
  return _RealtimeHarness(
    gateway: gateway,
    realtime: realtime,
    subscription: subscription,
    events: events,
  );
}

final class _RealtimeHarness {
  const _RealtimeHarness({
    required this.gateway,
    required this.realtime,
    required this.subscription,
    required this.events,
  });

  final _Gateway gateway;
  final SessionRealtimeService realtime;
  final StreamSubscription<InboxRealtimeEvent> subscription;
  final List<InboxRealtimeEvent> events;

  Future<void> dispose() async {
    await subscription.cancel();
    await realtime.dispose();
    await gateway.close();
  }
}

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

MattermostUserThreadDto _userThread({
  required String rootId,
  required String channelId,
  int unreadReplies = 1,
  int unreadMentions = 0,
  bool deletedRoot = false,
}) => MattermostUserThreadDto(
  id: rootId,
  replyCount: 1,
  lastReplyAt: 2,
  lastViewedAt: 0,
  participants: const <MattermostUserDto>[],
  post: MattermostPostDto(
    id: rootId,
    userId: 'other',
    channelId: channelId,
    message: 'Root',
    createAt: 1,
    deleteAt: deletedRoot ? 1 : 0,
  ),
  unreadReplies: unreadReplies,
  unreadMentions: unreadMentions,
);

MattermostPostDto _unreadPost({
  required String id,
  required String channelId,
  required int createAt,
}) => MattermostPostDto(
  id: id,
  userId: 'other',
  channelId: channelId,
  message: 'hello @me',
  createAt: createAt,
);

MattermostPostListDto _postList(List<MattermostPostDto> posts) =>
    MattermostPostListDto(
      order: posts.map((MattermostPostDto post) => post.id).toList(),
      posts: <String, MattermostPostDto>{
        for (final MattermostPostDto post in posts) post.id: post,
      },
      nextPostId: '',
      previousPostId: '',
      hasNext: false,
    );

MattermostInboxRepository _repository(
  _InboxApi api, [
  PostponedRepository? postponed,
  InboxSettingsRepository? settings,
]) => MattermostInboxRepository(
  api: api,
  messageMapper: const MattermostMessageMapper(),
  postponed: postponed ?? const _Postponed(),
  settings: settings,
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
    this.channelsByTeam = const <String, List<MattermostChannelDto>>{},
    this.membersByTeam = const <String, List<MattermostChannelMemberDto>>{},
    this.groupUsers = const MattermostGroupChannelUsersDto(
      usersByChannelId: <String, List<MattermostUserDto>>{},
    ),
    this.unreadPages = const <String, MattermostPostListDto>{},
    this.afterPages = const <String, MattermostPostListDto>{},
    this.threadsByTeam = const <String, List<MattermostUserThreadDto>>{},
    this.threadById = const <String, MattermostUserThreadDto>{},
    MattermostUserDto? currentUser,
    this.onCurrentUserRequest,
    this.onUnreadRequest,
    this.failUserLookup = false,
    this.failPostHydration = false,
  }) : currentUser =
           currentUser ?? const MattermostUserDto(id: 'me', username: 'me');
  final List<MattermostTeamDto> teams;
  final List<MattermostChannelDto> channels;
  final List<MattermostChannelMemberDto> members;
  final List<MattermostPostDto> unread;
  final List<MattermostUserDto> users;
  final Map<String, List<MattermostChannelDto>> channelsByTeam;
  final Map<String, List<MattermostChannelMemberDto>> membersByTeam;
  final MattermostGroupChannelUsersDto groupUsers;
  final Map<String, MattermostPostListDto> unreadPages;
  final Map<String, MattermostPostListDto> afterPages;
  final Map<String, List<MattermostUserThreadDto>> threadsByTeam;
  final Map<String, MattermostUserThreadDto> threadById;
  MattermostUserDto currentUser;
  final Future<void> Function()? onCurrentUserRequest;
  final Future<void> Function()? onUnreadRequest;
  final bool failUserLookup;
  final bool failPostHydration;
  int currentUserRequests = 0;
  int teamsRequests = 0;
  final List<String> channelRequestTeamIds = <String>[];
  final List<String> memberRequestTeamIds = <String>[];
  final List<String> unreadChannelIds = <String>[];
  final List<String> afterRequests = <String>[];
  final List<List<String>> postHydrationRequests = <List<String>>[];
  final List<List<String>> userLookupRequests = <List<String>>[];
  String? viewedChannelId;
  String? viewedUserId;
  String? readThreadId;
  String? readTeamId;
  int? readTimestamp;
  var threadRequests = 0;
  @override
  Future<MattermostUserDto> getCurrentUser() async {
    currentUserRequests++;
    await onCurrentUserRequest?.call();
    return currentUser;
  }

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() async {
    teamsRequests++;
    return teams;
  }

  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) async {
    channelRequestTeamIds.add(teamId);
    return channelsByTeam[teamId] ?? channels;
  }

  @override
  Future<List<MattermostChannelMemberDto>> getChannelMembersForUser({
    required String userId,
    required String teamId,
  }) async {
    memberRequestTeamIds.add(teamId);
    return membersByTeam[teamId] ?? members;
  }

  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) async {
    final List<MattermostUserThreadDto> threads =
        threadsByTeam[teamId] ?? const <MattermostUserThreadDto>[];
    return MattermostUserThreadsDto(
      total: threads.length,
      totalUnreadThreads: threads.length,
      totalUnreadMentions: threads.fold<int>(
        0,
        (int total, MattermostUserThreadDto thread) =>
            total + thread.unreadMentions,
      ),
      threads: threads,
    );
  }

  @override
  Future<MattermostUserThreadDto?> getUserThread({
    required String userId,
    required String teamId,
    required String threadId,
  }) async {
    threadRequests++;
    return threadById[threadId];
  }

  @override
  Future<MattermostPostListDto> getUnreadPostsForChannel({
    required String userId,
    required String channelId,
    int limitBefore = 0,
    int limitAfter = 200,
  }) async {
    unreadChannelIds.add(channelId);
    await onUnreadRequest?.call();
    final MattermostPostListDto? page = unreadPages[channelId];
    if (page != null) return page;
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
  Future<MattermostPostListDto> getPostsAfter({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) async {
    afterRequests.add('$channelId|$postId');
    return afterPages['$channelId|$postId'] ??
        const MattermostPostListDto(
          order: <String>[],
          posts: <String, MattermostPostDto>{},
          nextPostId: '',
          previousPostId: '',
          hasNext: false,
        );
  }

  @override
  Future<List<MattermostPostDto>> getPostsByIds(List<String> postIds) async {
    postHydrationRequests.add(List<String>.of(postIds));
    if (failPostHydration) throw StateError('post hydration failed');
    return unread.where((it) => postIds.contains(it.id)).toList();
  }

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    userLookupRequests.add(List<String>.of(userIds));
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

final class _StaticInboxSettings extends InboxSettingsRepository {
  _StaticInboxSettings(this.settings);

  final InboxSettings settings;
  var loads = 0;

  @override
  Future<InboxSettingsSnapshot> load({required AuthSession session}) async {
    loads++;
    return InboxSettingsSnapshot(
      settings: settings,
      state: InboxSettingsLoadState.parsed,
    );
  }

  @override
  Future<void> save({
    required AuthSession session,
    required InboxSettings settings,
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
