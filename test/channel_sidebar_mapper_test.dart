import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/mappers/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';

void main() {
  test('uses category channel order and adds uncategorized dialogs', () {
    final List<SidebarSection> sections = mapSections(
      channels: <SidebarChannel>[
        const SidebarChannel(
          id: 'channel-1',
          teamId: 'team-1',
          name: 'one',
          displayName: 'One',
          kind: ChannelKind.publicChannel,
        ),
        const SidebarChannel(
          id: 'channel-2',
          teamId: 'team-1',
          name: 'two',
          displayName: 'Two',
          kind: ChannelKind.privateChannel,
        ),
        const SidebarChannel(
          id: 'direct-1',
          teamId: '',
          name: 'me__user-2',
          displayName: 'Ada',
          kind: ChannelKind.directMessage,
        ),
      ],
      categories: const <MattermostChannelCategoryDto>[
        MattermostChannelCategoryDto(
          id: 'category-1',
          userId: 'user-1',
          teamId: 'team-1',
          type: 'custom',
          displayName: 'Product',
          sorting: 'manual',
          channelIds: <String>['channel-2', 'channel-1'],
          muted: false,
        ),
      ],
      categoryOrder: const <String>['category-1'],
    );

    expect(
      sections.map((SidebarSection section) => section.displayName),
      <String>['Product', 'Direct messages'],
    );
    expect(
      sections.first.channels.map((SidebarChannel channel) => channel.id),
      <String>['channel-2', 'channel-1'],
    );
    expect(sections.last.channels.single.id, 'direct-1');
  });

  test('uses the category order returned separately by the API', () {
    final List<SidebarSection> sections = mapSections(
      channels: const <SidebarChannel>[
        SidebarChannel(
          id: 'channel-1',
          teamId: 'team-1',
          name: 'one',
          displayName: 'One',
          kind: ChannelKind.publicChannel,
        ),
        SidebarChannel(
          id: 'channel-2',
          teamId: 'team-1',
          name: 'two',
          displayName: 'Two',
          kind: ChannelKind.publicChannel,
        ),
      ],
      categories: const <MattermostChannelCategoryDto>[
        MattermostChannelCategoryDto(
          id: 'category-1',
          userId: 'user-1',
          teamId: 'team-1',
          type: 'custom',
          displayName: 'First in payload',
          sorting: 'manual',
          channelIds: <String>['channel-1'],
          muted: false,
        ),
        MattermostChannelCategoryDto(
          id: 'category-2',
          userId: 'user-1',
          teamId: 'team-1',
          type: 'custom',
          displayName: 'First in sidebar',
          sorting: 'manual',
          channelIds: <String>['channel-2'],
          muted: false,
        ),
      ],
      categoryOrder: const <String>['category-2', 'category-1'],
    );

    expect(sections.map((SidebarSection section) => section.id), <String>[
      'category-2',
      'category-1',
    ]);
  });

  test('maps category presentation properties and sorts recent channels', () {
    final List<SidebarSection> sections = mapSections(
      channels: const <SidebarChannel>[
        SidebarChannel(
          id: 'older',
          teamId: 'team-1',
          name: 'older',
          displayName: 'Older',
          kind: ChannelKind.publicChannel,
          lastActivityAt: 100,
        ),
        SidebarChannel(
          id: 'newer',
          teamId: 'team-1',
          name: 'newer',
          displayName: 'Newer',
          kind: ChannelKind.publicChannel,
          lastActivityAt: 300,
        ),
        SidebarChannel(
          id: 'same-time',
          teamId: 'team-1',
          name: 'same-time',
          displayName: 'Same time',
          kind: ChannelKind.publicChannel,
          lastActivityAt: 100,
        ),
      ],
      categories: const <MattermostChannelCategoryDto>[
        MattermostChannelCategoryDto(
          id: 'category-1',
          userId: 'user-1',
          teamId: 'team-1',
          type: 'custom',
          displayName: 'Muted recent',
          sorting: 'recent',
          channelIds: <String>['older', 'same-time', 'newer'],
          muted: true,
          collapsed: true,
        ),
      ],
      categoryOrder: const <String>[],
    );

    expect(sections.single.collapsed, isTrue);
    expect(sections.single.muted, isTrue);
    expect(sections.single.sorting, ChannelSorting.recent);
    expect(
      sections.single.channels.map((SidebarChannel channel) => channel.id),
      <String>['newer', 'older', 'same-time'],
    );
  });

  test('treats empty sorting as manual', () {
    final List<SidebarSection> sections = mapSections(
      channels: const <SidebarChannel>[
        SidebarChannel(
          id: 'older',
          teamId: 'team-1',
          name: 'older',
          displayName: 'Older',
          kind: ChannelKind.publicChannel,
          lastActivityAt: 100,
        ),
        SidebarChannel(
          id: 'newer',
          teamId: 'team-1',
          name: 'newer',
          displayName: 'Newer',
          kind: ChannelKind.publicChannel,
          lastActivityAt: 300,
        ),
      ],
      categories: const <MattermostChannelCategoryDto>[
        MattermostChannelCategoryDto(
          id: 'category-1',
          userId: 'user-1',
          teamId: 'team-1',
          type: 'custom',
          displayName: 'Manual',
          sorting: '',
          channelIds: <String>['older', 'newer'],
          muted: false,
        ),
      ],
      categoryOrder: const <String>[],
    );

    expect(sections.single.sorting, ChannelSorting.manual);
    expect(
      sections.single.channels.map((SidebarChannel channel) => channel.id),
      <String>['older', 'newer'],
    );
  });

  test('maps all supported Mattermost channel types', () {
    for (final (String, ChannelKind) value in <(String, ChannelKind)>[
      ('O', ChannelKind.publicChannel),
      ('P', ChannelKind.privateChannel),
      ('D', ChannelKind.directMessage),
      ('G', ChannelKind.groupMessage),
    ]) {
      final SidebarChannel channel = mapChannel(
        MattermostChannelDto(
          id: 'id-${value.$1}',
          teamId: 'team-1',
          name: 'name',
          displayName: 'Display',
          type: value.$1,
        ),
      );
      expect(channel.kind, value.$2);
    }
  });

  test('maps unread state from root counters for ordinary channels', () {
    const MattermostChannelDto raw = MattermostChannelDto(
      id: 'channel-1',
      teamId: 'team-1',
      name: 'general',
      displayName: 'General',
      type: 'O',
      totalMessageCount: 20,
      totalMessageCountRoot: 8,
    );

    final SidebarChannel channel = mapChannelMembership(
      channel: mapChannel(raw),
      rawChannel: raw,
      member: const MattermostChannelMemberDto(
        channelId: 'channel-1',
        userId: 'me',
        msgCount: 20,
        msgCountRoot: 7,
      ),
    );

    expect(channel.isUnread, isTrue);
  });

  test('maps dialog unread state from full counters and mute preference', () {
    const MattermostChannelDto raw = MattermostChannelDto(
      id: 'dm-1',
      teamId: '',
      name: 'me__ada',
      displayName: '',
      type: 'D',
      totalMessageCount: 5,
      totalMessageCountRoot: 0,
    );

    final SidebarChannel channel = mapChannelMembership(
      channel: mapChannel(raw),
      rawChannel: raw,
      member: const MattermostChannelMemberDto(
        channelId: 'dm-1',
        userId: 'me',
        msgCount: 4,
        notifyProps: MattermostChannelNotifyPropsDto(markUnread: 'mention'),
      ),
    );

    expect(channel.isUnread, isTrue);
    expect(channel.muted, isTrue);
  });

  test('keeps the team handle on a mapped channel for post permalinks', () {
    final SidebarChannel channel = mapChannel(
      const MattermostChannelDto(
        id: 'channel-1',
        teamId: 'team-1',
        name: 'general',
        displayName: 'General',
        type: 'O',
      ),
      teamName: 'engineering',
    );

    expect(channel.teamName, 'engineering');
  });

  test('uses the latest of last_post_at and update_at for activity', () {
    final SidebarChannel channelWithPosts = mapChannel(
      const MattermostChannelDto(
        id: 'with-posts',
        teamId: 'team-1',
        name: 'with-posts',
        displayName: 'With posts',
        type: 'O',
        updateAt: 100,
        lastPostAt: 300,
      ),
    );
    final SidebarChannel channelWithoutRecentPosts = mapChannel(
      const MattermostChannelDto(
        id: 'without-recent-posts',
        teamId: 'team-1',
        name: 'without-recent-posts',
        displayName: 'Without recent posts',
        type: 'O',
        updateAt: 400,
        lastPostAt: 0,
      ),
    );

    expect(channelWithPosts.lastActivityAt, 300);
    expect(channelWithoutRecentPosts.lastActivityAt, 400);
  });
}
