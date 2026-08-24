import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/channels/data/channel_sidebar_store.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

void main() {
  test('persists sidebar order and scopes rows by account', () async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ChannelSidebarStore store = ChannelSidebarStore(database);
    const SidebarTeam team = SidebarTeam(
      id: 'team-1',
      displayName: 'Example team',
    );
    const List<SidebarSection> sections = <SidebarSection>[
      SidebarSection(
        id: 'category-1',
        displayName: 'Work',
        collapsed: true,
        muted: true,
        sorting: ChannelSorting.recent,
        channels: <SidebarChannel>[
          SidebarChannel(
            id: 'second',
            teamId: 'team-1',
            name: 'second',
            displayName: 'Second',
            kind: ChannelKind.privateChannel,
            lastActivityAt: 200,
          ),
          SidebarChannel(
            id: 'first',
            teamId: 'team-1',
            name: 'first',
            displayName: 'First',
            kind: ChannelKind.publicChannel,
          ),
        ],
      ),
    ];

    await store.replace('https://one.example', team, sections);

    final ChannelSidebarSnapshot restored = await store.read(
      'https://one.example',
    );
    final ChannelSidebarSnapshot otherAccount = await store.read(
      'https://two.example',
    );
    expect(restored.team?.displayName, 'Example team');
    expect(restored.sections.single.collapsed, isTrue);
    expect(restored.sections.single.muted, isTrue);
    expect(restored.sections.single.sorting, ChannelSorting.recent);
    expect(restored.sections.single.channels.first.lastActivityAt, 200);
    expect(
      restored.sections.single.channels.map(
        (SidebarChannel channel) => channel.id,
      ),
      <String>['second', 'first'],
    );
    expect(otherAccount.hasData, isFalse);
  });
}
