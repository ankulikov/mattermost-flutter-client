import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/posts/data/channel_post_cache_models.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

final class ChannelPostStore {
  ChannelPostStore(this._database);

  final db.AppDatabase _database;
  final StreamController<({String accountId, String channelId})> _changes =
      StreamController<({String accountId, String channelId})>.broadcast();

  Stream<ChannelPostSnapshot> watch({
    required String accountId,
    required String channelId,
  }) {
    final Stream<void> signals = Stream<void>.multi((
      MultiStreamController<void> controller,
    ) {
      final StreamSubscription<({String accountId, String channelId})>
      subscription = _changes.stream
          .where(
            (({String accountId, String channelId}) key) =>
                key.accountId == accountId && key.channelId == channelId,
          )
          .listen((_) => controller.add(null));
      controller.add(null);
      controller.onCancel = () => unawaited(subscription.cancel());
    });
    return signals.asyncMap(
      (_) => read(accountId: accountId, channelId: channelId),
    );
  }

  Future<ChannelPostSnapshot> read({
    required String accountId,
    required String channelId,
  }) async {
    final List<db.CachedChannelPost> postRows =
        await (_database.select(_database.cachedChannelPosts)..where(
              (db.CachedChannelPosts table) =>
                  table.accountId.equals(accountId) &
                  table.channelId.equals(channelId) &
                  table.deleteAt.equals(0),
            ))
            .get();
    final db.ChannelPostSyncState? sync =
        await (_database.select(_database.channelPostSyncStates)..where(
              (db.ChannelPostSyncStates table) =>
                  table.accountId.equals(accountId) &
                  table.channelId.equals(channelId),
            ))
            .getSingleOrNull();
    if (postRows.isEmpty) {
      return ChannelPostSnapshot(hasOlder: !(sync?.oldestComplete ?? false));
    }
    final Set<String> postIds = postRows
        .map((db.CachedChannelPost row) => row.postId)
        .toSet();
    final Set<String> authorIds = postRows
        .map((db.CachedChannelPost row) => row.userId)
        .toSet();
    final List<db.CachedPostAuthor> authorRows =
        await (_database.select(_database.cachedPostAuthors)..where(
              (db.CachedPostAuthors table) =>
                  table.accountId.equals(accountId) &
                  table.userId.isIn(authorIds),
            ))
            .get();
    final List<db.CachedPostReaction> reactionRows =
        await (_database.select(_database.cachedPostReactions)..where(
              (db.CachedPostReactions table) =>
                  table.accountId.equals(accountId) &
                  table.postId.isIn(postIds),
            ))
            .get();
    final Map<String, String> names = <String, String>{
      for (final db.CachedPostAuthor row in authorRows)
        row.userId: row.displayName,
    };
    final Map<String, List<PostReaction>> reactions =
        <String, List<PostReaction>>{};
    for (final db.CachedPostReaction row in reactionRows) {
      reactions
          .putIfAbsent(row.postId, () => <PostReaction>[])
          .add(
            PostReaction(
              emoji: _emojiLabel(row.emojiName),
              count: row.reactionCount,
              reactedByCurrentUser: row.reactedByCurrentUser,
            ),
          );
    }
    final List<ChannelPost> posts =
        postRows
            .map(
              (db.CachedChannelPost row) => ChannelPost(
                id: row.postId,
                channelId: row.channelId,
                author: PostAuthor(
                  id: row.userId,
                  displayName: names[row.userId] ?? row.userId,
                ),
                sentAt: DateTime.fromMillisecondsSinceEpoch(row.createAt),
                message: row.message,
                reactions: List<PostReaction>.unmodifiable(
                  reactions[row.postId] ?? const <PostReaction>[],
                ),
              ),
            )
            .toList(growable: false)
          ..sort((ChannelPost a, ChannelPost b) {
            final int byTime = a.sentAt.compareTo(b.sentAt);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          });
    return ChannelPostSnapshot(
      posts: List<ChannelPost>.unmodifiable(posts),
      hasOlder: !(sync?.oldestComplete ?? false),
    );
  }

  Future<String?> oldestPostId({
    required String accountId,
    required String channelId,
  }) async {
    final db.ChannelPostSyncState? row =
        await (_database.select(_database.channelPostSyncStates)..where(
              (db.ChannelPostSyncStates table) =>
                  table.accountId.equals(accountId) &
                  table.channelId.equals(channelId),
            ))
            .getSingleOrNull();
    return row?.oldestPostId;
  }

  Future<void> savePage({
    required String accountId,
    required String channelId,
    required PostCachePage page,
    required bool isLatestPage,
  }) async {
    await _database.transaction(() async {
      final db.ChannelPostSyncState? oldSync =
          await (_database.select(_database.channelPostSyncStates)..where(
                (db.ChannelPostSyncStates table) =>
                    table.accountId.equals(accountId) &
                    table.channelId.equals(channelId),
              ))
              .getSingleOrNull();
      for (final PostCacheAuthor author in page.authors) {
        await _database
            .into(_database.cachedPostAuthors)
            .insertOnConflictUpdate(
              db.CachedPostAuthorsCompanion.insert(
                accountId: accountId,
                userId: author.id,
                displayName: author.displayName,
              ),
            );
      }
      for (final PostCacheItem post in page.posts) {
        await _database
            .into(_database.cachedChannelPosts)
            .insertOnConflictUpdate(
              db.CachedChannelPostsCompanion.insert(
                accountId: accountId,
                postId: post.id,
                channelId: post.channelId,
                userId: post.userId,
                createAt: post.createAt,
                updateAt: post.updateAt,
                deleteAt: Value<int>(post.deleteAt),
                message: post.message,
              ),
            );
        await _database
            .into(_database.channelPostOrders)
            .insertOnConflictUpdate(
              db.ChannelPostOrdersCompanion.insert(
                accountId: accountId,
                channelId: channelId,
                postId: post.id,
                createAt: post.createAt,
              ),
            );
        await (_database.delete(_database.cachedPostReactions)..where(
              (db.CachedPostReactions table) =>
                  table.accountId.equals(accountId) &
                  table.postId.equals(post.id),
            ))
            .go();
        for (final PostCacheReaction reaction in post.reactions) {
          await _database
              .into(_database.cachedPostReactions)
              .insert(
                db.CachedPostReactionsCompanion.insert(
                  accountId: accountId,
                  postId: post.id,
                  emojiName: reaction.emojiName,
                  reactionCount: reaction.count,
                  reactedByCurrentUser: reaction.reactedByCurrentUser,
                ),
              );
        }
      }
      final String? pageOldest = page.order.isEmpty ? null : page.order.last;
      final bool keepExistingOldest = isLatestPage && oldSync != null;
      await _database
          .into(_database.channelPostSyncStates)
          .insertOnConflictUpdate(
            db.ChannelPostSyncStatesCompanion.insert(
              accountId: accountId,
              channelId: channelId,
              oldestPostId: Value<String?>(
                keepExistingOldest ? oldSync.oldestPostId : pageOldest,
              ),
              oldestComplete: Value<bool>(
                keepExistingOldest
                    ? oldSync.oldestComplete
                    : page.oldestComplete,
              ),
              lastSyncedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    });
    _changes.add((accountId: accountId, channelId: channelId));
  }

  Future<void> close() => _changes.close();

  static String _emojiLabel(String name) => switch (name) {
    '+1' || 'thumbsup' => '👍',
    'heart' => '❤️',
    'tada' => '🎉',
    _ => ':$name:',
  };
}
