import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/repositories/user_preferences_repository.dart';

/// Stores one JSON preferences document for a durable account scope.
final class DriftUserPreferencesRepository
    implements UserPreferencesRepository {
  const DriftUserPreferencesRepository({
    required db.AppDatabase database,
    required String accountScopeId,
  }) : _database = database,
       _accountScopeId = accountScopeId;

  final db.AppDatabase _database;
  final String _accountScopeId;

  @override
  Future<UserPreferences> read() async {
    final db.UserPreferencesRow? row = await _readRow();
    if (row == null) return UserPreferences.defaults;
    return _decode(row.preferencesJson);
  }

  @override
  Future<void> update(UserPreferences preferences) async {
    await _database.transaction(() async {
      final db.UserPreferencesRow? existing = await _readRow();
      final Map<String, Object?> document = existing == null
          ? <String, Object?>{}
          : _decodeDocument(existing.preferencesJson);
      document['theme'] = preferences.theme.name;
      await _database
          .into(_database.userPreferencesRows)
          .insertOnConflictUpdate(
            db.UserPreferencesRowsCompanion.insert(
              accountId: _accountScopeId,
              preferencesJson: jsonEncode(document),
            ),
          );
    });
  }

  @override
  Future<DateTime?> readLastUpdateCheck() async {
    return (await _readRow())?.lastCheckUpdate?.toUtc();
  }

  @override
  Future<void> writeLastUpdateCheck(DateTime checkedAt) async {
    await _database.transaction(() async {
      final Value<DateTime?> timestamp = Value<DateTime?>(checkedAt.toUtc());
      final int updated =
          await (_database.update(_database.userPreferencesRows)..where(
                (db.$UserPreferencesRowsTable table) =>
                    table.accountId.equals(_accountScopeId),
              ))
              .write(
                db.UserPreferencesRowsCompanion(lastCheckUpdate: timestamp),
              );
      if (updated != 0) return;

      await _database
          .into(_database.userPreferencesRows)
          .insert(
            db.UserPreferencesRowsCompanion.insert(
              accountId: _accountScopeId,
              preferencesJson: jsonEncode(<String, Object?>{
                'theme': UserPreferences.defaults.theme.name,
              }),
              lastCheckUpdate: timestamp,
            ),
          );
    });
  }

  Future<db.UserPreferencesRow?> _readRow() {
    return (_database.select(_database.userPreferencesRows)..where(
          (db.$UserPreferencesRowsTable table) =>
              table.accountId.equals(_accountScopeId),
        ))
        .getSingleOrNull();
  }
}

UserPreferences _decode(String source) {
  final Object? theme = _decodeDocument(source)['theme'];
  return UserPreferences(
    theme: switch (theme) {
      'dark' => ThemePreference.dark,
      'light' || _ => ThemePreference.light,
    },
  );
}

Map<String, Object?> _decodeDocument(String source) {
  try {
    final Object? decoded = jsonDecode(source);
    if (decoded is Map<String, Object?>) {
      return Map<String, Object?>.of(decoded);
    }
  } on FormatException {
    // A corrupt row must not prevent the application from starting.
  }
  return <String, Object?>{};
}
