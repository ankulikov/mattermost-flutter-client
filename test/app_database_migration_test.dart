import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('drops all obsolete volatile cache tables', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-volatile-tables-',
    );
    final File file = File('${directory.path}/cache.sqlite');
    final sqlite.Database legacy = sqlite.sqlite3.open(file.path);
    const List<String> obsoleteTables = <String>[
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
    ];
    for (final String table in obsoleteTables) {
      legacy.execute('CREATE TABLE $table (id TEXT NOT NULL)');
    }
    legacy.execute('PRAGMA user_version = 6');
    legacy.close();

    final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
    try {
      final List<String> remaining = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row.read<String>('name'))
          .get();
      expect(remaining, isNot(containsAll(obsoleteTables)));
      expect(remaining.where(obsoleteTables.contains), isEmpty);
      expect(remaining, contains('cached_user_profiles'));
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test('creates the user profile cache when upgrading schema 7', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-user-profiles-',
    );
    final File file = File('${directory.path}/cache.sqlite');
    sqlite.sqlite3.open(file.path)
      ..execute('PRAGMA user_version = 7')
      ..close();

    final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
    try {
      final List<String> tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row.read<String>('name'))
          .get();
      expect(tables, contains('cached_user_profiles'));
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'adds complete card fields when upgrading user cache schema 8',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mattermost-user-profile-fields-',
      );
      final File file = File('${directory.path}/cache.sqlite');
      final sqlite.Database legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE cached_user_profiles (
        account_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        username TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        PRIMARY KEY (account_id, user_id)
      )
    ''');
      legacy.execute('PRAGMA user_version = 8');
      legacy.close();

      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      try {
        final List<String> columns = await database
            .customSelect('PRAGMA table_info(cached_user_profiles)')
            .map((row) => row.read<String>('name'))
            .get();
        expect(
          columns,
          containsAll(<String>[
            'nickname',
            'position',
            'email',
            'profile_image_updated_at',
          ]),
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'adds the account-scoped username index when upgrading schema 9',
    () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'mattermost-user-profile-index-',
      );
      final File file = File('${directory.path}/cache.sqlite');
      final sqlite.Database legacy = sqlite.sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE cached_user_profiles (
        account_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL,
        username TEXT NOT NULL,
        nickname TEXT NOT NULL DEFAULT '',
        position TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        profile_image_updated_at INTEGER NOT NULL DEFAULT 0,
        expires_at INTEGER NOT NULL,
        PRIMARY KEY (account_id, user_id)
      )
    ''');
      legacy.execute('PRAGMA user_version = 9');
      legacy.close();

      final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
      try {
        final List<String> indexes = await database
            .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
            .map((row) => row.read<String>('name'))
            .get();
        expect(indexes, contains('cached_user_profiles_account_username_idx'));
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('creates recent emoji storage when upgrading schema 10', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-recent-emojis-',
    );
    final File file = File('${directory.path}/cache.sqlite');
    sqlite.sqlite3.open(file.path)
      ..execute('PRAGMA user_version = 10')
      ..close();

    final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
    try {
      final List<String> tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row.read<String>('name'))
          .get();
      expect(tables, contains('recent_emojis'));
      final List<String> columns = await database
          .customSelect('PRAGMA table_info(recent_emojis)')
          .map((row) => row.read<String>('name'))
          .get();
      expect(columns, contains('last_used_at'));
      expect(columns, isNot(contains('position')));
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
