import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;

const int maximumRecentEmojis = 27;

abstract interface class RecentEmojiCache {
  Future<List<String>> read(String accountId);

  Future<void> remember({required String accountId, required String emojiName});
}

final class DriftRecentEmojiCache implements RecentEmojiCache {
  DriftRecentEmojiCache(this._database, {int Function()? timestamp})
    : _timestamp = timestamp ?? _currentTimestamp;

  final db.AppDatabase _database;
  final int Function() _timestamp;
  int _lastTimestamp = 0;

  @override
  Future<List<String>> read(String accountId) async {
    final List<db.RecentEmoji> rows =
        await (_database.select(_database.recentEmojis)
              ..where(
                (db.$RecentEmojisTable table) =>
                    table.accountId.equals(accountId),
              )
              ..orderBy(<OrderClauseGenerator<db.$RecentEmojisTable>>[
                (db.$RecentEmojisTable table) =>
                    OrderingTerm.desc(table.lastUsedAt),
                (db.$RecentEmojisTable table) =>
                    OrderingTerm.asc(table.emojiName),
              ])
              ..limit(maximumRecentEmojis))
            .get();
    return rows
        .map((db.RecentEmoji row) => row.emojiName)
        .toList(growable: false);
  }

  @override
  Future<void> remember({
    required String accountId,
    required String emojiName,
  }) async {
    final String normalized = emojiName.trim().toLowerCase();
    if (normalized.isEmpty) return;
    await _database.transaction(() async {
      await _database
          .into(_database.recentEmojis)
          .insertOnConflictUpdate(
            db.RecentEmojisCompanion.insert(
              accountId: accountId,
              emojiName: normalized,
              lastUsedAt: _nextTimestamp(),
            ),
          );

      final List<db.RecentEmoji> overflow =
          await (_database.select(_database.recentEmojis)
                ..where(
                  (db.$RecentEmojisTable table) =>
                      table.accountId.equals(accountId),
                )
                ..orderBy(<OrderClauseGenerator<db.$RecentEmojisTable>>[
                  (db.$RecentEmojisTable table) =>
                      OrderingTerm.desc(table.lastUsedAt),
                  (db.$RecentEmojisTable table) =>
                      OrderingTerm.asc(table.emojiName),
                ])
                ..limit(maximumRecentEmojis + 1))
              .get();
      if (overflow.length <= maximumRecentEmojis) return;

      final db.RecentEmoji oldest = overflow.last;
      await (_database.delete(_database.recentEmojis)..where(
            (db.$RecentEmojisTable table) =>
                table.accountId.equals(oldest.accountId) &
                table.emojiName.equals(oldest.emojiName),
          ))
          .go();
    });
  }

  int _nextTimestamp() {
    final int current = _timestamp();
    _lastTimestamp = current > _lastTimestamp ? current : _lastTimestamp + 1;
    return _lastTimestamp;
  }
}

int _currentTimestamp() => DateTime.now().microsecondsSinceEpoch;
