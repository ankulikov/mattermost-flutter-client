import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/data/database/inbox_counter_cache.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_counters.dart';

void main() {
  late db.AppDatabase database;
  late DriftInboxCounterCache cache;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    cache = DriftInboxCounterCache(database);
  });

  tearDown(() => database.close());

  test('stores and replaces counts independently for each account', () async {
    expect(await cache.load('missing'), same(InboxCounters.empty));

    await cache.save(
      'account-a',
      const InboxCounters(newMessages: 4, postponedMessages: 2),
    );
    await cache.save(
      'account-b',
      const InboxCounters(newMessages: 7, postponedMessages: 3),
    );
    await cache.save(
      'account-a',
      const InboxCounters(newMessages: 1, postponedMessages: 5),
    );

    final InboxCounters first = await cache.load('account-a');
    final InboxCounters second = await cache.load('account-b');
    expect(first.newMessages, 1);
    expect(first.postponedMessages, 5);
    expect(second.newMessages, 7);
    expect(second.postponedMessages, 3);
  });
}
