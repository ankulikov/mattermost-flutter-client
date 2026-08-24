import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/channels/data/channel_sidebar_store.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('migrates sidebar presentation fields from schema version 1', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'mattermost-migration-',
    );
    final File file = File('${directory.path}/sidebar.sqlite');
    final sqlite.Database legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE sidebar_teams (
        account_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        PRIMARY KEY (account_id, team_id)
      );
      CREATE TABLE sidebar_channels (
        account_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        name TEXT NOT NULL,
        display_name TEXT NOT NULL,
        kind INTEGER NOT NULL,
        PRIMARY KEY (account_id, channel_id)
      );
      CREATE TABLE sidebar_categories (
        account_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        team_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (account_id, category_id)
      );
      CREATE TABLE sidebar_category_channels (
        account_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        channel_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (account_id, category_id, channel_id)
      );
      INSERT INTO sidebar_teams VALUES ('account-1', 'team-1', 'Team');
      INSERT INTO sidebar_channels
        VALUES ('account-1', 'channel-1', 'team-1', 'channel', 'Channel', 0);
      INSERT INTO sidebar_categories
        VALUES ('account-1', 'category-1', 'team-1', 'Category', 0);
      INSERT INTO sidebar_category_channels
        VALUES ('account-1', 'category-1', 'channel-1', 0);
      PRAGMA user_version = 1;
    ''');
    legacy.close();

    final db.AppDatabase database = db.AppDatabase(NativeDatabase(file));
    try {
      final ChannelSidebarSnapshot snapshot = await ChannelSidebarStore(
        database,
      ).read('account-1');

      expect(snapshot.sections.single.collapsed, isFalse);
      expect(snapshot.sections.single.muted, isFalse);
      expect(snapshot.sections.single.sorting, ChannelSorting.manual);
      expect(snapshot.sections.single.channels.single.lastActivityAt, 0);
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
