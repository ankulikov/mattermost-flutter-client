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

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{accountId, channelId};
}

class SidebarCategories extends Table {
  TextColumn get accountId => text()();
  TextColumn get categoryId => text()();
  TextColumn get teamId => text()();
  TextColumn get displayName => text()();
  IntColumn get position => integer()();

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

@DriftDatabase(
  tables: <Type>[
    SidebarTeams,
    SidebarChannels,
    SidebarCategories,
    SidebarCategoryChannels,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  factory AppDatabase.open() => AppDatabase(openDatabaseConnection());

  @override
  int get schemaVersion => 1;
}
