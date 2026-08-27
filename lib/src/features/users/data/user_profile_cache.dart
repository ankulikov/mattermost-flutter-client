import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;

final class CachedUserProfile {
  const CachedUserProfile({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.expiresAt,
  });

  final String userId;
  final String firstName;
  final String lastName;
  final String username;
  final DateTime expiresAt;
}

abstract interface class UserProfileCache {
  Future<CachedUserProfile?> getById({
    required String accountId,
    required String userId,
  });

  Future<List<CachedUserProfile>> getByIds({
    required String accountId,
    required List<String> userIds,
  });

  Future<void> upsertAll({
    required String accountId,
    required List<CachedUserProfile> profiles,
  });
}

final class DriftUserProfileCache implements UserProfileCache {
  const DriftUserProfileCache(this._database);

  final db.AppDatabase _database;

  @override
  Future<CachedUserProfile?> getById({
    required String accountId,
    required String userId,
  }) async {
    final db.CachedUserProfile? row =
        await (_database.select(_database.cachedUserProfiles)..where(
              (db.$CachedUserProfilesTable table) =>
                  table.accountId.equals(accountId) &
                  table.userId.equals(userId),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<CachedUserProfile>> getByIds({
    required String accountId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return const <CachedUserProfile>[];
    final List<db.CachedUserProfile> rows =
        await (_database.select(_database.cachedUserProfiles)..where(
              (db.$CachedUserProfilesTable table) =>
                  table.accountId.equals(accountId) &
                  table.userId.isIn(userIds),
            ))
            .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> upsertAll({
    required String accountId,
    required List<CachedUserProfile> profiles,
  }) async {
    if (profiles.isEmpty) return;
    await _database.batch((Batch batch) {
      batch.insertAllOnConflictUpdate(
        _database.cachedUserProfiles,
        profiles
            .map(
              (CachedUserProfile profile) => db.CachedUserProfilesCompanion(
                accountId: Value<String>(accountId),
                userId: Value<String>(profile.userId),
                firstName: Value<String>(profile.firstName),
                lastName: Value<String>(profile.lastName),
                username: Value<String>(profile.username),
                expiresAt: Value<DateTime>(profile.expiresAt),
              ),
            )
            .toList(growable: false),
      );
    });
  }

  static CachedUserProfile _fromRow(db.CachedUserProfile row) =>
      CachedUserProfile(
        userId: row.userId,
        firstName: row.firstName,
        lastName: row.lastName,
        username: row.username,
        expiresAt: row.expiresAt,
      );
}
