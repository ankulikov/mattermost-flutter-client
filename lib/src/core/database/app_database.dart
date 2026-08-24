import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/core/database/open_database.dart';

part 'app_database.g.dart';

class SidebarTeams extends Table {
  TextColumn get accountId => text()();
  TextColumn get teamId => text()();
  TextColumn get displayName => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, teamId};
}

class SidebarChannels extends Table {
  TextColumn get accountId => text()();
  TextColumn get channelId => text()();
  TextColumn get teamId => text()();
  TextColumn get name => text()();
  TextColumn get displayName => text()();
  IntColumn get kind => integer()();
  IntColumn get lastActivityAt =>
      integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, channelId};
}

class SidebarCategories extends Table {
  TextColumn get accountId => text()();
  TextColumn get categoryId => text()();
  TextColumn get teamId => text()();
  TextColumn get displayName => text()();
  IntColumn get position => integer()();
  BoolColumn get collapsed => boolean().withDefault(const Constant(false))();
  BoolColumn get muted => boolean().withDefault(const Constant(false))();
  IntColumn get sorting => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, categoryId};
}

class SidebarCategoryChannels extends Table {
  TextColumn get accountId => text()();
  TextColumn get categoryId => text()();
  TextColumn get channelId => text()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    accountId,
    categoryId,
    channelId,
  };
}

class CachedPostAuthors extends Table {
  TextColumn get accountId => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, userId};
}

class CachedChannelPosts extends Table {
  TextColumn get accountId => text()();
  TextColumn get postId => text()();
  TextColumn get channelId => text()();
  TextColumn get userId => text()();
  IntColumn get createAt => integer()();
  IntColumn get updateAt => integer()();
  IntColumn get deleteAt => integer().withDefault(const Constant<int>(0))();
  TextColumn get message => text()();

  /// `null` is reserved for rows migrated from a schema that did not persist
  /// thread membership. New rows always contain either `''` (a root) or the
  /// root post id (a reply), so unknown legacy replies never leak into history.
  TextColumn get rootId => text().nullable()();
  IntColumn get replyCount => integer().withDefault(const Constant<int>(0))();
  IntColumn get lastReplyAt => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, postId};
}

/// Server order is kept separately from post contents so pagination can evolve
/// without making the wire DTO or a timestamp the UI's ordering contract.
class ChannelPostOrders extends Table {
  TextColumn get accountId => text()();
  TextColumn get channelId => text()();
  TextColumn get postId => text()();
  IntColumn get createAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    accountId,
    channelId,
    postId,
  };
}

/// Raw membership of the currently contiguous channel-history segment.
/// Unlike [ChannelPostOrders], this includes replies and is used only to prove
/// that a refreshed page overlaps the segment before retaining its deep cursor.
class ChannelHistoryEntries extends Table {
  TextColumn get accountId => text()();
  TextColumn get channelId => text()();
  TextColumn get postId => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    accountId,
    channelId,
    postId,
  };
}

class CachedPostReactions extends Table {
  TextColumn get accountId => text()();
  TextColumn get postId => text()();
  TextColumn get emojiName => text()();
  IntColumn get reactionCount => integer()();
  BoolColumn get reactedByCurrentUser => boolean()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    accountId,
    postId,
    emojiName,
  };
}

class ChannelPostSyncStates extends Table {
  TextColumn get accountId => text()();
  TextColumn get channelId => text()();
  TextColumn get oldestPostId => text().nullable()();
  BoolColumn get oldestComplete =>
      boolean().withDefault(const Constant(false))();
  IntColumn get lastSyncedAt => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, channelId};
}

class ThreadSyncStates extends Table {
  TextColumn get accountId => text()();
  TextColumn get rootPostId => text()();
  TextColumn get channelId => text()();
  BoolColumn get complete => boolean().withDefault(const Constant(false))();
  IntColumn get lastSyncedAt => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, rootPostId};
}

@DriftDatabase(
  tables: <Type>[
    SidebarTeams,
    SidebarChannels,
    SidebarCategories,
    SidebarCategoryChannels,
    CachedPostAuthors,
    CachedChannelPosts,
    ChannelPostOrders,
    ChannelHistoryEntries,
    CachedPostReactions,
    ChannelPostSyncStates,
    ThreadSyncStates,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(openDatabaseConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 2) {
        await migrator.addColumn(
          sidebarChannels,
          sidebarChannels.lastActivityAt,
        );
        await migrator.addColumn(
          sidebarCategories,
          sidebarCategories.collapsed,
        );
        await migrator.addColumn(sidebarCategories, sidebarCategories.muted);
        await migrator.addColumn(sidebarCategories, sidebarCategories.sorting);
      }
      if (from < 3) {
        await migrator.createTable(cachedPostAuthors);
        await migrator.createTable(cachedChannelPosts);
        await migrator.createTable(channelPostOrders);
        await migrator.createTable(cachedPostReactions);
        await migrator.createTable(channelPostSyncStates);
      }
      if (from < 4) {
        if (from >= 3) {
          await migrator.addColumn(
            cachedChannelPosts,
            cachedChannelPosts.rootId,
          );
          await migrator.addColumn(
            cachedChannelPosts,
            cachedChannelPosts.replyCount,
          );
          await migrator.addColumn(
            cachedChannelPosts,
            cachedChannelPosts.lastReplyAt,
          );
        }
        await migrator.createTable(threadSyncStates);
      }
      if (from < 5) {
        await migrator.createTable(channelHistoryEntries);
      }
      if (from >= 4 && from < 6) {
        await migrator.deleteTable('thread_post_orders');
      }
    },
  );
}
