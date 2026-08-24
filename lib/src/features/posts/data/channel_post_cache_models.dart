final class PostCacheAuthor {
  const PostCacheAuthor({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

final class PostCacheReaction {
  const PostCacheReaction({
    required this.emojiName,
    required this.count,
    required this.reactedByCurrentUser,
  });

  final String emojiName;
  final int count;
  final bool reactedByCurrentUser;
}

final class PostCacheItem {
  const PostCacheItem({
    required this.id,
    required this.channelId,
    required this.userId,
    required this.createAt,
    required this.updateAt,
    required this.deleteAt,
    required this.message,
    required this.reactions,
    this.rootId = '',
    this.replyCount = 0,
    this.lastReplyAt = 0,
  });

  final String id;
  final String channelId;
  final String userId;
  final int createAt;
  final int updateAt;
  final int deleteAt;
  final String message;
  final List<PostCacheReaction> reactions;
  final String rootId;
  final int replyCount;
  final int lastReplyAt;
}

final class PostCachePage {
  const PostCachePage({
    required this.posts,
    required this.authors,
    required this.order,
    required this.oldestComplete,
  });

  final List<PostCacheItem> posts;
  final List<PostCacheAuthor> authors;
  final List<String> order;
  final bool oldestComplete;
}
