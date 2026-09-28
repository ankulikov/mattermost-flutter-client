import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/data/database/user_group_membership_cache.dart';

void main() {
  late db.AppDatabase database;
  late DriftUserGroupMembershipCache cache;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    cache = DriftUserGroupMembershipCache(database);
  });

  tearDown(() => database.close());

  test('replaces one account snapshot without changing another', () async {
    final DateTime now = DateTime.utc(2026, 9, 28);
    CachedUserGroup group(String id) => CachedUserGroup(
      groupId: id,
      name: id,
      displayName: id,
      allowReference: true,
      deleteAt: 0,
      expiresAt: now.add(const Duration(days: 1)),
    );

    await cache.replaceAll(
      accountId: 'account-a',
      groups: <CachedUserGroup>[group('old')],
    );
    await cache.replaceAll(
      accountId: 'account-b',
      groups: <CachedUserGroup>[group('other')],
    );
    await cache.replaceAll(
      accountId: 'account-a',
      groups: <CachedUserGroup>[group('new')],
    );

    expect(
      (await cache.getFresh(accountId: 'account-a', now: now)).single.name,
      'new',
    );
    expect(
      (await cache.getFresh(accountId: 'account-b', now: now)).single.name,
      'other',
    );
  });

  test('does not return expired membership', () async {
    final DateTime now = DateTime.utc(2026, 9, 28);
    await cache.replaceAll(
      accountId: 'account',
      groups: <CachedUserGroup>[
        CachedUserGroup(
          groupId: 'expired',
          name: 'expired',
          displayName: 'Expired',
          allowReference: true,
          deleteAt: 0,
          expiresAt: now.subtract(const Duration(seconds: 1)),
        ),
      ],
    );

    expect(await cache.getFresh(accountId: 'account', now: now), isEmpty);
  });
}
