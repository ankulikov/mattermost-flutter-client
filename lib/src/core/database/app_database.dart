import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/core/database/open_database.dart';

part 'app_database.g.dart';

/// Drift remains the persistence boundary for future durable data such as user
/// profiles. Channel navigation, posts, threads, and paging state are volatile
/// and deliberately do not have database tables.
@DriftDatabase(tables: <Type>[])
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(openDatabaseConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) => migrator.createAll(),
    onUpgrade: (Migrator migrator, int from, int to) async {
      if (from >= 7) return;
      for (final String table in _removedVolatileTables) {
        await customStatement('DROP TABLE IF EXISTS $table');
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
