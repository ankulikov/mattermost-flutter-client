import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

final class ChannelSidebarStore {
  ChannelSidebarStore(this._database);

  final db.AppDatabase _database;
  final Map<String, ({bool refreshing, bool failed})> _syncStates =
      <String, ({bool refreshing, bool failed})>{};
  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  Stream<ChannelSidebarSnapshot> watch(String accountId) {
    final Stream<String> signals = Stream<String>.multi((
      MultiStreamController<String> controller,
    ) {
      final StreamSubscription<String> subscription = _changes.stream
          .where((String changedAccountId) => changedAccountId == accountId)
          .listen(controller.add);
      controller.add(accountId);
      controller.onCancel = () => unawaited(subscription.cancel());
    });
    return signals.asyncMap((String _) => read(accountId));
  }

  Future<void> close() => _changes.close();

  Future<ChannelSidebarSnapshot> read(String accountId) async {
    final db.SidebarTeam? teamRow =
        await (_database.select(_database.sidebarTeams)..where(
              (db.SidebarTeams table) => table.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    final List<db.SidebarCategory> categoryRows =
        await (_database.select(_database.sidebarCategories)
              ..where(
                (db.SidebarCategories table) =>
                    table.accountId.equals(accountId),
              )
              ..orderBy(<OrderClauseGenerator<db.SidebarCategories>>[
                (db.SidebarCategories table) =>
                    OrderingTerm.asc(table.position),
              ]))
            .get();
    final List<db.SidebarChannel> channelRows =
        await (_database.select(_database.sidebarChannels)..where(
              (db.SidebarChannels table) => table.accountId.equals(accountId),
            ))
            .get();
    final List<db.SidebarCategoryChannel> placementRows =
        await (_database.select(_database.sidebarCategoryChannels)
              ..where(
                (db.SidebarCategoryChannels table) =>
                    table.accountId.equals(accountId),
              )
              ..orderBy(<OrderClauseGenerator<db.SidebarCategoryChannels>>[
                (db.SidebarCategoryChannels table) =>
                    OrderingTerm.asc(table.position),
              ]))
            .get();
    final Map<String, SidebarChannel> channels = <String, SidebarChannel>{
      for (final db.SidebarChannel row in channelRows)
        row.channelId: SidebarChannel(
          id: row.channelId,
          teamId: row.teamId,
          name: row.name,
          displayName: row.displayName,
          kind: ChannelKind.values[row.kind],
          lastActivityAt: row.lastActivityAt,
        ),
    };
    final Map<String, List<SidebarChannel>> channelsByCategory =
        <String, List<SidebarChannel>>{};
    for (final db.SidebarCategoryChannel placement in placementRows) {
      final SidebarChannel? channel = channels[placement.channelId];
      if (channel != null) {
        channelsByCategory
            .putIfAbsent(placement.categoryId, () => <SidebarChannel>[])
            .add(channel);
      }
    }
    final ({bool refreshing, bool failed}) sync =
        _syncStates[accountId] ?? (refreshing: false, failed: false);
    return ChannelSidebarSnapshot(
      team: teamRow == null
          ? null
          : SidebarTeam(id: teamRow.teamId, displayName: teamRow.displayName),
      sections: categoryRows
          .map(
            (db.SidebarCategory row) => SidebarSection(
              id: row.categoryId,
              displayName: row.displayName,
              channels: List<SidebarChannel>.unmodifiable(
                channelsByCategory[row.categoryId] ?? <SidebarChannel>[],
              ),
              collapsed: row.collapsed,
              muted: row.muted,
              sorting: ChannelSorting.values[row.sorting],
            ),
          )
          .toList(growable: false),
      isRefreshing: sync.refreshing,
      refreshFailed: sync.failed,
    );
  }

  void setSyncState(
    String accountId, {
    required bool refreshing,
    required bool failed,
  }) {
    _syncStates[accountId] = (refreshing: refreshing, failed: failed);
    _changes.add(accountId);
  }

  Future<void> replace(
    String accountId,
    SidebarTeam? team,
    List<SidebarSection> sections,
  ) async {
    await _database.transaction(() async {
      await (_database.delete(_database.sidebarCategoryChannels)..where(
            (db.SidebarCategoryChannels table) =>
                table.accountId.equals(accountId),
          ))
          .go();
      await (_database.delete(_database.sidebarCategories)..where(
            (db.SidebarCategories table) => table.accountId.equals(accountId),
          ))
          .go();
      await (_database.delete(_database.sidebarChannels)..where(
            (db.SidebarChannels table) => table.accountId.equals(accountId),
          ))
          .go();
      await (_database.delete(_database.sidebarTeams)..where(
            (db.SidebarTeams table) => table.accountId.equals(accountId),
          ))
          .go();
      if (team == null) return;
      await _database
          .into(_database.sidebarTeams)
          .insert(
            db.SidebarTeamsCompanion.insert(
              accountId: accountId,
              teamId: team.id,
              displayName: team.displayName,
            ),
          );
      final Map<String, SidebarChannel> uniqueChannels =
          <String, SidebarChannel>{
            for (final SidebarSection section in sections)
              for (final SidebarChannel channel in section.channels)
                channel.id: channel,
          };
      await _database.batch((Batch batch) {
        batch.insertAll(
          _database.sidebarChannels,
          uniqueChannels.values
              .map(
                (SidebarChannel channel) => db.SidebarChannelsCompanion.insert(
                  accountId: accountId,
                  channelId: channel.id,
                  teamId: channel.teamId,
                  name: channel.name,
                  displayName: channel.displayName,
                  kind: channel.kind.index,
                  lastActivityAt: Value<int>(channel.lastActivityAt),
                ),
              )
              .toList(growable: false),
        );
        batch.insertAll(
          _database.sidebarCategories,
          <db.SidebarCategoriesCompanion>[
            for (final MapEntry<int, SidebarSection> entry
                in sections.asMap().entries)
              db.SidebarCategoriesCompanion.insert(
                accountId: accountId,
                categoryId: entry.value.id,
                teamId: team.id,
                displayName: entry.value.displayName,
                position: entry.key,
                collapsed: Value<bool>(entry.value.collapsed),
                muted: Value<bool>(entry.value.muted),
                sorting: Value<int>(entry.value.sorting.index),
              ),
          ],
        );
        batch.insertAll(
          _database.sidebarCategoryChannels,
          <db.SidebarCategoryChannelsCompanion>[
            for (final SidebarSection section in sections)
              for (final MapEntry<int, SidebarChannel> entry
                  in section.channels.asMap().entries)
                db.SidebarCategoryChannelsCompanion.insert(
                  accountId: accountId,
                  categoryId: section.id,
                  channelId: entry.value.id,
                  position: entry.key,
                ),
          ],
        );
      });
    });
    _syncStates[accountId] = (refreshing: false, failed: false);
    _changes.add(accountId);
  }
}
