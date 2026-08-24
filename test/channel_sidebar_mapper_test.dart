import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/features/channels/data/channel_sidebar_mapper.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

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
}
