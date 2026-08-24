import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/database/app_database.dart' as db;
import 'package:mattermost_flutter/src/features/posts/data/channel_post_cache_models.dart';
import 'package:mattermost_flutter/src/features/posts/data/channel_post_store.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';

void main() {
  test('persists paged posts and scopes the cache by account', () async {
    final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final ChannelPostStore store = ChannelPostStore(database);
    addTearDown(store.close);

    await store.savePage(
      accountId: 'account-a',
      channelId: 'channel-1',
      page: _page(
        ids: const <String>['post-3', 'post-2'],
        oldestComplete: false,
      ),
      isLatestPage: true,
    );

    ChannelPostSnapshot snapshot = await store.read(
      accountId: 'account-a',
      channelId: 'channel-1',
    );
    expect(snapshot.posts.map((post) => post.id), const <String>[
      'post-2',
      'post-3',
    ]);
    expect(snapshot.posts.last.author.displayName, 'Ada Lovelace');
    expect(snapshot.posts.last.reactions.single.emoji, '👍');
    expect(snapshot.hasOlder, isTrue);
    expect(
      await store
          .read(accountId: 'account-b', channelId: 'channel-1')
          .then((ChannelPostSnapshot value) => value.posts),
      isEmpty,
    );

    await store.savePage(
      accountId: 'account-a',
      channelId: 'channel-1',
      page: _page(ids: const <String>['post-1'], oldestComplete: true),
      isLatestPage: false,
    );
    snapshot = await store.read(accountId: 'account-a', channelId: 'channel-1');
    expect(snapshot.posts.map((post) => post.id), const <String>[
      'post-1',
      'post-2',
      'post-3',
    ]);
    expect(snapshot.hasOlder, isFalse);
    expect(
      await store.oldestPostId(accountId: 'account-a', channelId: 'channel-1'),
      'post-1',
    );
  });

  test(
    'keeps replies out of channel history and stores orphan membership',
    () async {
      final db.AppDatabase database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final ChannelPostStore store = ChannelPostStore(database);
      addTearDown(store.close);

      await store.savePage(
        accountId: 'account-a',
        channelId: 'channel-1',
        page: PostCachePage(
          order: const <String>['reply-1', 'root-1'],
          oldestComplete: true,
          authors: const <PostCacheAuthor>[
            PostCacheAuthor(id: 'ada', displayName: 'Ada'),
          ],
          posts: const <PostCacheItem>[
            PostCacheItem(
              id: 'reply-1',
              channelId: 'channel-1',
              userId: 'ada',
              createAt: 2000,
              updateAt: 2000,
              deleteAt: 0,
              message: 'reply',
              rootId: 'missing-root',
              reactions: <PostCacheReaction>[],
            ),
            PostCacheItem(
              id: 'root-1',
              channelId: 'channel-1',
              userId: 'ada',
              createAt: 1000,
              updateAt: 1000,
              deleteAt: 0,
              message: 'root',
              replyCount: 2,
              reactions: <PostCacheReaction>[],
            ),
          ],
        ),
        isLatestPage: true,
      );

      final ChannelPostSnapshot snapshot = await store.read(
        accountId: 'account-a',
        channelId: 'channel-1',
      );
      expect(snapshot.posts.map((post) => post.id), const <String>['root-1']);
      expect(snapshot.posts.single.replyCount, 2);
      final List<db.ThreadPostOrder> threadRows = await database
          .select(database.threadPostOrders)
          .get();
      expect(threadRows.single.rootPostId, 'missing-root');
      expect(threadRows.single.postId, 'reply-1');
    },
  );
}

PostCachePage _page({required List<String> ids, required bool oldestComplete}) {
  return PostCachePage(
    order: ids,
    oldestComplete: oldestComplete,
    authors: const <PostCacheAuthor>[
      PostCacheAuthor(id: 'ada', displayName: 'Ada Lovelace'),
    ],
    posts: ids
        .map(
          (String id) => PostCacheItem(
            id: id,
            channelId: 'channel-1',
            userId: 'ada',
            createAt: int.parse(id.substring(id.length - 1)) * 1000,
            updateAt: int.parse(id.substring(id.length - 1)) * 1000,
            deleteAt: 0,
            message: id,
            reactions: const <PostCacheReaction>[
              PostCacheReaction(
                emojiName: '+1',
                count: 2,
                reactedByCurrentUser: true,
              ),
            ],
          ),
        )
        .toList(growable: false),
  );
}
