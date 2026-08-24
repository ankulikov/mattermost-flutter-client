final class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final Uri? avatarUrl;
}

final class PostReaction {
  const PostReaction({
    required this.emoji,
    required this.count,
    this.reactedByCurrentUser = false,
  }) : assert(count > 0, 'A visible reaction must have a positive count.');

  final String emoji;
  final int count;
  final bool reactedByCurrentUser;
}

final class ChannelPost {
  const ChannelPost({
    required this.id,
    required this.channelId,
    required this.author,
    required this.sentAt,
    required this.message,
    this.reactions = const <PostReaction>[],
    this.rootId = '',
    this.replyCount = 0,
    this.lastReplyAt,
  });

  final String id;
  final String channelId;
  final PostAuthor author;
  final DateTime sentAt;
  final String message;
  final List<PostReaction> reactions;
  final String rootId;
  final int replyCount;
  final DateTime? lastReplyAt;

  bool get isReply => rootId.isNotEmpty;
}
