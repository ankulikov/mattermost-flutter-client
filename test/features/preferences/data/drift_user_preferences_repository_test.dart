import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/preferences/data/repositories/drift_user_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';

void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  DriftUserPreferencesRepository repository(String accountScopeId) {
    return DriftUserPreferencesRepository(
      database: database,
      accountScopeId: accountScopeId,
    );
  }

  group('DriftUserPreferencesRepository', () {
    test('returns light defaults when the account has no row', () async {
      expect(await repository('account-a').read(), UserPreferences.defaults);
    });

    test('updates and reads preferences within the account scope', () async {
      await repository(
        'account-a',
      ).update(const UserPreferences(theme: ThemePreference.dark));

      expect(
        await repository('account-a').read(),
        const UserPreferences(theme: ThemePreference.dark),
      );
      expect(await repository('account-b').read(), UserPreferences.defaults);
    });

    test('falls back safely for malformed and unsupported documents', () async {
      for (final String preferencesJson in <String>[
        '{not-json',
        '[]',
        '{}',
        '{"theme":null}',
        '{"theme":42}',
        '{"theme":"system"}',
      ]) {
        await database
            .into(database.userPreferencesRows)
            .insertOnConflictUpdate(
              db.UserPreferencesRowsCompanion.insert(
                accountId: 'account-a',
                preferencesJson: preferencesJson,
              ),
            );

        expect(
          await repository('account-a').read(),
          UserPreferences.defaults,
          reason: preferencesJson,
        );
      }
    });

    test('preserves unknown fields while updating known preferences', () async {
      await database
          .into(database.userPreferencesRows)
          .insert(
            db.UserPreferencesRowsCompanion.insert(
              accountId: 'account-a',
              preferencesJson: jsonEncode(<String, Object?>{
                'theme': 'light',
                'futureSetting': <String, Object?>{'enabled': true},
              }),
            ),
          );

      await repository(
        'account-a',
      ).update(const UserPreferences(theme: ThemePreference.dark));

      final db.UserPreferencesRow row = await database
          .select(database.userPreferencesRows)
          .getSingle();
      expect(jsonDecode(row.preferencesJson), <String, Object?>{
        'theme': 'dark',
        'futureSetting': <String, Object?>{'enabled': true},
      });
    });
  });
}
