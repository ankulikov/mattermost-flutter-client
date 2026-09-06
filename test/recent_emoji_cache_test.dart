import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart';
import 'package:mattermost_flutter/src/data/database/recent_emoji_cache.dart';

void main() {
  test('updates only the selected emoji timestamp', () async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var timestamp = 100;
    final DriftRecentEmojiCache cache = DriftRecentEmojiCache(
      database,
      timestamp: () => timestamp += 1,
    );

    await cache.remember(accountId: 'account-a', emojiName: 'smile');
    await cache.remember(accountId: 'account-a', emojiName: 'wave');
    final Map<String, int> before = <String, int>{
      for (final RecentEmoji row
          in await database.select(database.recentEmojis).get())
        row.emojiName: row.lastUsedAt,
    };

    await cache.remember(accountId: 'account-a', emojiName: 'smile');
    final Map<String, int> after = <String, int>{
      for (final RecentEmoji row
          in await database.select(database.recentEmojis).get())
        row.emojiName: row.lastUsedAt,
    };

    expect(await cache.read('account-a'), <String>['smile', 'wave']);
    expect(after['smile'], greaterThan(before['smile']!));
    expect(after['wave'], before['wave']);
  });

  test('keeps an account-scoped bounded MRU list', () async {
    final AppDatabase database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var timestamp = 1000;
    final DriftRecentEmojiCache cache = DriftRecentEmojiCache(
      database,
      timestamp: () => timestamp += 1,
    );

    for (var index = 0; index < 30; index += 1) {
      await cache.remember(accountId: 'account-a', emojiName: 'emoji_$index');
    }
    await cache.remember(accountId: 'account-a', emojiName: 'emoji_10');
    await cache.remember(accountId: 'account-b', emojiName: 'other');

    final List<String> first = await cache.read('account-a');
    expect(first, hasLength(maximumRecentEmojis));
    expect(first.first, 'emoji_10');
    expect(first.where((String value) => value == 'emoji_10'), hasLength(1));
    expect(await cache.read('account-b'), <String>['other']);

    final List<RecentEmoji> stored = await database
        .select(database.recentEmojis)
        .get();
    expect(stored, hasLength(maximumRecentEmojis + 1));
    expect(
      stored
          .singleWhere(
            (RecentEmoji row) =>
                row.accountId == 'account-a' && row.emojiName == 'emoji_10',
          )
          .lastUsedAt,
      timestamp - 1,
    );
  });
}
