import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;

final class CachedUserGroup {
  const CachedUserGroup({
    required this.groupId,
    required this.name,
    required this.displayName,
    required this.allowReference,
    required this.deleteAt,
    required this.expiresAt,
  });

  final String groupId;
  final String name;
  final String displayName;
  final bool allowReference;
  final int deleteAt;
  final DateTime expiresAt;
}

/// Durable, account-scoped fallback for current user-group membership.
abstract interface class UserGroupMembershipCache {
  Future<List<CachedUserGroup>> getFresh({
    required String accountId,
    required DateTime now,
  });

  /// Atomically replaces the complete membership snapshot for [accountId].
  Future<void> replaceAll({
    required String accountId,
    required List<CachedUserGroup> groups,
  });
}

final class DriftUserGroupMembershipCache implements UserGroupMembershipCache {
  const DriftUserGroupMembershipCache(this._database);

  final db.AppDatabase _database;

  @override
  Future<List<CachedUserGroup>> getFresh({
    required String accountId,
    required DateTime now,
  }) async {
    final List<db.CachedUserGroup> rows =
        await (_database.select(_database.cachedUserGroups)..where(
              (db.$CachedUserGroupsTable table) =>
                  table.accountId.equals(accountId) &
                  table.expiresAt.isBiggerThanValue(now),
            ))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> replaceAll({
    required String accountId,
    required List<CachedUserGroup> groups,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(_database.cachedUserGroups)..where(
            (db.$CachedUserGroupsTable table) =>
                table.accountId.equals(accountId),
          ))
          .go();
      if (groups.isEmpty) return;
      await _database.batch((Batch batch) {
        batch.insertAll(
          _database.cachedUserGroups,
          groups
              .map(
                (CachedUserGroup group) => db.CachedUserGroupsCompanion.insert(
                  accountId: accountId,
                  groupId: group.groupId,
                  name: group.name,
                  displayName: group.displayName,
                  allowReference: group.allowReference,
                  deleteAt: group.deleteAt,
                  expiresAt: group.expiresAt,
                ),
              )
              .toList(growable: false),
        );
      });
    });
  }

  static CachedUserGroup _fromRow(db.CachedUserGroup row) => CachedUserGroup(
    groupId: row.groupId,
    name: row.name,
    displayName: row.displayName,
    allowReference: row.allowReference,
    deleteAt: row.deleteAt,
    expiresAt: row.expiresAt,
  );
}
