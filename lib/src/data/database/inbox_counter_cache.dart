import 'package:mattermost_flutter/src/data/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_counters.dart';

abstract interface class InboxCounterCache {
  Future<InboxCounters> load(String accountId);

  Future<void> save(String accountId, InboxCounters counters);
}

final class DriftInboxCounterCache implements InboxCounterCache {
  const DriftInboxCounterCache(this._database);

  final db.AppDatabase _database;

  @override
  Future<InboxCounters> load(String accountId) async {
    final db.InboxCounter? row =
        await (_database.select(_database.inboxCounters)..where(
              (db.$InboxCountersTable table) =>
                  table.accountId.equals(accountId),
            ))
            .getSingleOrNull();
    if (row == null) return InboxCounters.empty;
    return InboxCounters(
      newMessages: row.newMessageCount.clamp(0, 0x7fffffff),
      postponedMessages: row.postponedMessageCount.clamp(0, 0x7fffffff),
    );
  }

  @override
  Future<void> save(String accountId, InboxCounters counters) => _database
      .into(_database.inboxCounters)
      .insertOnConflictUpdate(
        db.InboxCountersCompanion.insert(
          accountId: accountId,
          newMessageCount: counters.newMessages.clamp(0, 0x7fffffff),
          postponedMessageCount: counters.postponedMessages.clamp(
            0,
            0x7fffffff,
          ),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
}
