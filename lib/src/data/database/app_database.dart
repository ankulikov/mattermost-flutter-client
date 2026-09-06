import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/data/database/open_database.dart';

part 'app_database.g.dart';

/// A tenant-scoped, expiring projection of the user fields needed to render
/// names. Avatar bytes and avatar version metadata deliberately live elsewhere.
@TableIndex.sql(
  'CREATE INDEX cached_user_profiles_account_username_idx '
  'ON cached_user_profiles (account_id, username COLLATE NOCASE)',
)
class CachedUserProfiles extends Table {
  TextColumn get accountId => text()();

  TextColumn get userId => text()();

  TextColumn get firstName => text()();

  TextColumn get lastName => text()();

  TextColumn get username => text()();

  TextColumn get nickname => text().withDefault(const Constant<String>(''))();

  TextColumn get position => text().withDefault(const Constant<String>(''))();

  TextColumn get email => text().withDefault(const Constant<String>(''))();

  IntColumn get profileImageUpdatedAt =>
      integer().withDefault(const Constant<int>(0))();

  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, userId};
}

/// Per-account MRU reaction names. Content and post identifiers are not stored.
@TableIndex.sql(
  'CREATE INDEX recent_emojis_account_last_used_at_idx '
  'ON recent_emojis (account_id, last_used_at DESC)',
)
class RecentEmojis extends Table {
  TextColumn get accountId => text()();

  TextColumn get emojiName => text()();

  IntColumn get lastUsedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, emojiName};
}

/// Drift persists only explicitly owned durable data. Channel navigation,
/// posts, threads, and paging state remain volatile.
@DriftDatabase(tables: <Type>[CachedUserProfiles, RecentEmojis])
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(openDatabaseConnection());

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from < 7) {
        for (final String table in _removedVolatileTables) {
          await customStatement('DROP TABLE IF EXISTS $table');
        }
      }
      if (from < 8) {
        await migrator.createTable(cachedUserProfiles);
      }
      if (from >= 8 && from < 9) {
        await migrator.addColumn(
          cachedUserProfiles,
          cachedUserProfiles.nickname,
        );
        await migrator.addColumn(
          cachedUserProfiles,
          cachedUserProfiles.position,
        );
        await migrator.addColumn(cachedUserProfiles, cachedUserProfiles.email);
        await migrator.addColumn(
          cachedUserProfiles,
          cachedUserProfiles.profileImageUpdatedAt,
        );
      }
      if (from < 10) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS '
          'cached_user_profiles_account_username_idx '
          'ON cached_user_profiles (account_id, username COLLATE NOCASE)',
        );
      }
      if (from < 11) {
        await migrator.createTable(recentEmojis);
      }
    },
  );
}

const List<String> _removedVolatileTables = <String>[
  'sidebar_teams',
  'sidebar_channels',
  'sidebar_categories',
  'sidebar_category_channels',
  'cached_post_authors',
  'cached_channel_posts',
  'channel_post_orders',
  'channel_history_entries',
  'cached_post_reactions',
  'channel_post_sync_states',
  'thread_sync_states',
  // Removed in schema 6, included for installations that skipped that build.
  'thread_post_orders',
];
