import 'dart:async';

import 'package:drift/drift.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_client_factory.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/auth/data/credential_store.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';

final class ApiThreadRepository implements ThreadRepository {
  ApiThreadRepository({
    required CredentialStore credentialStore,
    required db.AppDatabase database,
    MattermostApiFactory clientFactory = const MattermostClientFactory(),
  }) : _credentialStore = credentialStore,
       _database = database,
       _clientFactory = clientFactory;

  static const int pageSize = 60;
  static const int maxPagesPerRefresh = 20;

  final CredentialStore _credentialStore;
  final db.AppDatabase _database;
  final MattermostApiFactory _clientFactory;
  final StreamController<({String accountId, String rootPostId})> _changes =
      StreamController<({String accountId, String rootPostId})>.broadcast();

  Future<void> close() => _changes.close();

  @override
  Stream<MessageThread> watch({
    required String accountId,
    required String rootPostId,
  }) async* {
    yield await read(accountId: accountId, rootPostId: rootPostId);
    await for (final _ in _changes.stream.where(
      (key) => key.accountId == accountId && key.rootPostId == rootPostId,
    )) {
      yield await read(accountId: accountId, rootPostId: rootPostId);
    }
  }

  @override
  Future<MessageThread> read({
    required String accountId,
    required String rootPostId,
  }) async {
    final List<db.CachedChannelPost> postRows =
        await (_database.select(_database.cachedChannelPosts)..where(
              (table) =>
                  table.accountId.equals(accountId) &
                  (table.postId.equals(rootPostId) |
                      table.rootId.equals(rootPostId)) &
                  table.deleteAt.equals(0),
            ))
            .get();
    final List<ChannelPost> posts = await _mapRows(accountId, postRows);
    final ChannelPost? root = posts
        .where((post) => post.id == rootPostId)
        .firstOrNull;
    final List<ChannelPost> replies =
        posts.where((post) => post.rootId == rootPostId).toList(growable: false)
          ..sort(_comparePosts);
    final db.ThreadSyncState? sync =
        await (_database.select(_database.threadSyncStates)..where(
              (table) =>
                  table.accountId.equals(accountId) &
                  table.rootPostId.equals(rootPostId),
            ))
            .getSingleOrNull();
    return MessageThread(
      rootPostId: rootPostId,
      root: root,
      replies: List<ChannelPost>.unmodifiable(replies),
      isComplete: sync?.complete ?? false,
    );
  }

  @override
  Future<void> refresh({
    required AuthSession session,
    required String rootPostId,
  }) async {
    final MattermostApi api = await _apiFor(session);
    final Map<String, MattermostPostDto> posts = <String, MattermostPostDto>{};
    final List<String> order = <String>[];
    String? fromPost;
    int? fromCreateAt;
    var hasNext = true;
    var page = 0;
    while (hasNext && page < maxPagesPerRefresh) {
      final MattermostPostListDto response = await api.getPostThread(
        rootPostId: rootPostId,
        perPage: pageSize,
        fromPost: fromPost,
        fromCreateAt: fromCreateAt,
      );
      posts.addAll(response.posts);
      for (final String id in response.order) {
        if (!order.contains(id)) order.add(id);
      }
      hasNext = response.hasNext;
      if (!hasNext || response.order.isEmpty) break;
      final String lastId = response.order.last;
      final MattermostPostDto? last = response.posts[lastId];
      if (last == null || lastId == fromPost) break;
      fromPost = lastId;
      fromCreateAt = last.createAt;
      page += 1;
    }
    final Set<String> userIds = posts.values
        .map((post) => post.userId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final List<MattermostUserDto> users = await api.getUsersByIds(
      userIds.toList(growable: false),
    );
    await _save(
      accountId: session.accountId,
      rootPostId: rootPostId,
      posts: posts,
      users: users,
      complete: !hasNext,
      currentUserId: session.userId,
    );
  }

  Future<void> _save({
    required String accountId,
    required String rootPostId,
    required Map<String, MattermostPostDto> posts,
    required List<MattermostUserDto> users,
    required bool complete,
    required String currentUserId,
  }) async {
    final MattermostPostDto? root = posts[rootPostId];
    final String channelId =
        root?.channelId ??
        posts.values.map((post) => post.channelId).firstOrNull ??
        '';
    await _database.transaction(() async {
      for (final MattermostUserDto user in users) {
        await _database
            .into(_database.cachedPostAuthors)
            .insertOnConflictUpdate(
              db.CachedPostAuthorsCompanion.insert(
                accountId: accountId,
                userId: user.id,
                displayName: _displayName(user),
              ),
            );
      }
      for (final MattermostPostDto post in posts.values) {
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
                rootId: Value<String?>(post.rootId),
                replyCount: Value<int>(post.replyCount),
                lastReplyAt: Value<int>(post.lastReplyAt),
              ),
            );
        await (_database.delete(_database.cachedPostReactions)..where(
              (table) =>
                  table.accountId.equals(accountId) &
                  table.postId.equals(post.id),
            ))
            .go();
        final Map<String, List<MattermostReactionDto>> grouped =
            <String, List<MattermostReactionDto>>{};
        for (final MattermostReactionDto reaction
            in post.metadata?.reactions ?? const <MattermostReactionDto>[]) {
          grouped.putIfAbsent(reaction.emojiName, () => []).add(reaction);
        }
        for (final entry in grouped.entries) {
          await _database
              .into(_database.cachedPostReactions)
              .insert(
                db.CachedPostReactionsCompanion.insert(
                  accountId: accountId,
                  postId: post.id,
                  emojiName: entry.key,
                  reactionCount: entry.value.length,
                  reactedByCurrentUser: entry.value.any(
                    (reaction) => reaction.userId == currentUserId,
                  ),
                ),
              );
        }
      }
      if (complete) {
        final Set<String> returnedIds = posts.keys.toSet();
        await (_database.update(_database.cachedChannelPosts)..where(
              (table) =>
                  table.accountId.equals(accountId) &
                  table.rootId.equals(rootPostId) &
                  table.postId.isNotIn(returnedIds) &
                  table.deleteAt.equals(0),
            ))
            .write(
              db.CachedChannelPostsCompanion(
                deleteAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
              ),
            );
      }
      await _database
          .into(_database.threadSyncStates)
          .insertOnConflictUpdate(
            db.ThreadSyncStatesCompanion.insert(
              accountId: accountId,
              rootPostId: rootPostId,
              channelId: channelId,
              complete: Value<bool>(complete),
              lastSyncedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
            ),
          );
    });
    _changes.add((accountId: accountId, rootPostId: rootPostId));
  }

  Future<List<ChannelPost>> _mapRows(
    String accountId,
    List<db.CachedChannelPost> rows,
  ) async {
    if (rows.isEmpty) return const <ChannelPost>[];
    final Set<String> authorIds = rows.map((row) => row.userId).toSet();
    final Set<String> postIds = rows.map((row) => row.postId).toSet();
    final List<db.CachedPostAuthor> authors =
        await (_database.select(_database.cachedPostAuthors)..where(
              (table) =>
                  table.accountId.equals(accountId) &
                  table.userId.isIn(authorIds),
            ))
            .get();
    final List<db.CachedPostReaction> reactions =
        await (_database.select(_database.cachedPostReactions)..where(
              (table) =>
                  table.accountId.equals(accountId) &
                  table.postId.isIn(postIds),
            ))
            .get();
    final Map<String, String> names = <String, String>{
      for (final row in authors) row.userId: row.displayName,
    };
    final Map<String, List<PostReaction>> reactionsByPost = {};
    for (final row in reactions) {
      reactionsByPost
          .putIfAbsent(row.postId, () => [])
          .add(
            PostReaction(
              emoji: _emojiLabel(row.emojiName),
              count: row.reactionCount,
              reactedByCurrentUser: row.reactedByCurrentUser,
            ),
          );
    }
    return rows
        .map(
          (row) => ChannelPost(
            id: row.postId,
            channelId: row.channelId,
            author: PostAuthor(
              id: row.userId,
              displayName: names[row.userId] ?? row.userId,
            ),
            sentAt: DateTime.fromMillisecondsSinceEpoch(row.createAt),
            message: row.message,
            reactions: List.unmodifiable(
              reactionsByPost[row.postId] ?? const [],
            ),
            rootId: row.rootId ?? '',
            replyCount: row.replyCount,
            lastReplyAt: row.lastReplyAt == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(row.lastReplyAt),
          ),
        )
        .toList(growable: false);
  }

  Future<MattermostApi> _apiFor(AuthSession session) async {
    final credentials = await _credentialStore.read();
    if (credentials == null || credentials.serverUrl != session.serverUrl) {
      throw StateError('No credentials for active Mattermost account');
    }
    return _clientFactory.create(
      serverUrl: credentials.serverUrl,
      token: credentials.token,
    );
  }

  static int _comparePosts(ChannelPost a, ChannelPost b) {
    final int time = a.sentAt.compareTo(b.sentAt);
    return time != 0 ? time : a.id.compareTo(b.id);
  }

  static String _displayName(MattermostUserDto user) {
    final String fullName = '${user.firstName} ${user.lastName}'.trim();
    if (fullName.isNotEmpty) return fullName;
    if (user.nickname.isNotEmpty) return user.nickname;
    return user.username.isEmpty ? user.id : user.username;
  }

  static String _emojiLabel(String name) => switch (name) {
    '+1' || 'thumbsup' => '👍',
    'heart' => '❤️',
    'tada' => '🎉',
    _ => ':$name:',
  };
}
