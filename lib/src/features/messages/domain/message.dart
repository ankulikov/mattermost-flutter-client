import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji.dart';

final class PostAuthor {
  const PostAuthor({
    required this.id,
    required this.displayName,
    this.profileImageUpdatedAt = 0,
  });

  final String id;
  final String displayName;

  /// Version used to invalidate this user's cached Mattermost profile image.
  final int profileImageUpdatedAt;
}

final class PostReaction {
  const PostReaction({
    required this.emoji,
    required this.count,
    String? emojiName,
    this.reactedByCurrentUser = false,
  }) : emojiName = emojiName ?? emoji,
       assert(count > 0, 'A visible reaction must have a positive count.');

  /// Human-readable label, such as `👍` or `:party_parrot:`.
  final String emoji;

  /// Mattermost's canonical name used by the reactions API.
  final String emojiName;
  final int count;
  final bool reactedByCurrentUser;

  PostReaction copyWith({int? count, bool? reactedByCurrentUser}) =>
      PostReaction(
        emoji: emoji,
        emojiName: emojiName,
        count: count ?? this.count,
        reactedByCurrentUser: reactedByCurrentUser ?? this.reactedByCurrentUser,
      );
}

/// Shared message entity used by channel, thread, and followed-thread slices.
final class ChannelPost {
  const ChannelPost({
    required this.id,
    required this.channelId,
    required this.author,
    required this.sentAt,
    required this.message,
    this.customEmojis = const <CustomEmojiReference>[],
    this.reactions = const <PostReaction>[],
    this.rootId = '',
    this.replyCount = 0,
    this.lastReplyAt,
    this.isDeleted = false,
  });

  final String id;
  final String channelId;
  final PostAuthor author;
  final DateTime sentAt;
  final String message;
  final List<CustomEmojiReference> customEmojis;
  final List<PostReaction> reactions;
  final String rootId;
  final int replyCount;
  final DateTime? lastReplyAt;
  final bool isDeleted;

  bool get isReply => rootId.isNotEmpty;

  ChannelPost withThreadSummary({
    required int replyCount,
    DateTime? lastReplyAt,
  }) => ChannelPost(
    id: id,
    channelId: channelId,
    author: author,
    sentAt: sentAt,
    message: message,
    customEmojis: customEmojis,
    reactions: reactions,
    rootId: rootId,
    replyCount: replyCount,
    lastReplyAt: lastReplyAt,
    isDeleted: isDeleted,
  );

  ChannelPost withReactions(List<PostReaction> reactions) => ChannelPost(
    id: id,
    channelId: channelId,
    author: author,
    sentAt: sentAt,
    message: message,
    customEmojis: customEmojis,
    reactions: List<PostReaction>.unmodifiable(reactions),
    rootId: rootId,
    replyCount: replyCount,
    lastReplyAt: lastReplyAt,
    isDeleted: isDeleted,
  );
}

ChannelPost toggleCurrentUserReaction(ChannelPost post, String emojiName) {
  final int index = post.reactions.indexWhere(
    (PostReaction reaction) => reaction.emojiName == emojiName,
  );
  if (index < 0) {
    return post.withReactions(<PostReaction>[
      ...post.reactions,
      PostReaction(
        emoji: ':$emojiName:',
        emojiName: emojiName,
        count: 1,
        reactedByCurrentUser: true,
      ),
    ]);
  }

  final PostReaction reaction = post.reactions[index];
  final List<PostReaction> reactions = List<PostReaction>.of(post.reactions);
  if (reaction.reactedByCurrentUser) {
    if (reaction.count == 1) {
      reactions.removeAt(index);
    } else {
      reactions[index] = reaction.copyWith(
        count: reaction.count - 1,
        reactedByCurrentUser: false,
      );
    }
  } else {
    reactions[index] = reaction.copyWith(
      count: reaction.count + 1,
      reactedByCurrentUser: true,
    );
  }
  return post.withReactions(reactions);
}

int compareMessagesBySentAt(ChannelPost first, ChannelPost second) {
  final int byTime = first.sentAt.compareTo(second.sentAt);
  return byTime != 0 ? byTime : first.id.compareTo(second.id);
}
