import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';

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
    this.userIds = const <String>[],
  }) : emojiName = emojiName ?? emoji,
       assert(count > 0, 'A visible reaction must have a positive count.');

  /// Human-readable label, such as `👍` or `:party_parrot:`.
  final String emoji;

  /// Mattermost's canonical name used by the reactions API.
  final String emojiName;
  final int count;
  final bool reactedByCurrentUser;
  final List<String> userIds;

  PostReaction copyWith({
    int? count,
    bool? reactedByCurrentUser,
    List<String>? userIds,
  }) => PostReaction(
    emoji: emoji,
    emojiName: emojiName,
    count: count ?? this.count,
    reactedByCurrentUser: reactedByCurrentUser ?? this.reactedByCurrentUser,
    userIds: userIds ?? this.userIds,
  );
}

final class PostAttachment {
  const PostAttachment({
    required this.id,
    required this.name,
    required this.size,
    required this.mimeType,
    this.extension = '',
    this.width = 0,
    this.height = 0,
    this.hasPreviewImage = false,
  });

  final String id;
  final String name;
  final int size;
  final String mimeType;
  final String extension;
  final int width;
  final int height;
  final bool hasPreviewImage;

  bool get isImage =>
      mimeType.toLowerCase().startsWith('image/') || (width > 0 && height > 0);
}

/// Shared message entity used by channel and thread scenarios.
final class Post {
  const Post({
    required this.id,
    required this.channelId,
    required this.author,
    required this.sentAt,
    this.updatedAt,
    required this.message,
    this.customEmojis = const <CustomEmojiReference>[],
    this.attachments = const <PostAttachment>[],
    this.richAttachments = const <RichAttachment>[],
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

  /// Last server-side revision time used to reject stale REST/realtime races.
  ///
  /// Hand-built posts without protocol metadata fall back to [sentAt].
  final DateTime? updatedAt;
  final String message;
  final List<CustomEmojiReference> customEmojis;
  final List<PostAttachment> attachments;
  final List<RichAttachment> richAttachments;
  final List<PostReaction> reactions;
  final String rootId;
  final int replyCount;
  final DateTime? lastReplyAt;
  final bool isDeleted;

  bool get isReply => rootId.isNotEmpty;

  DateTime get revisionAt => updatedAt ?? sentAt;

  /// Whether this post has content a message surface can render.
  ///
  /// Rich cards and uploaded files remain visible even when Mattermost sends
  /// an empty plain-text message. Deleted posts deliberately expose only their
  /// deletion placeholder, not their former content.
  bool get hasVisibleContent =>
      !isDeleted &&
      (message.trim().isNotEmpty ||
          attachments.isNotEmpty ||
          richAttachments.isNotEmpty);

  Post withThreadSummary({required int replyCount, DateTime? lastReplyAt}) =>
      Post(
        id: id,
        channelId: channelId,
        author: author,
        sentAt: sentAt,
        updatedAt: updatedAt,
        message: message,
        customEmojis: customEmojis,
        attachments: attachments,
        richAttachments: richAttachments,
        reactions: reactions,
        rootId: rootId,
        replyCount: replyCount,
        lastReplyAt: lastReplyAt,
        isDeleted: isDeleted,
      );

  Post withReactions(List<PostReaction> reactions) => Post(
    id: id,
    channelId: channelId,
    author: author,
    sentAt: sentAt,
    updatedAt: updatedAt,
    message: message,
    customEmojis: customEmojis,
    attachments: attachments,
    richAttachments: richAttachments,
    reactions: List<PostReaction>.unmodifiable(reactions),
    rootId: rootId,
    replyCount: replyCount,
    lastReplyAt: lastReplyAt,
    isDeleted: isDeleted,
  );
}

/// Backwards-compatible name retained while UI scenarios still use it.
@Deprecated('Use Post.')
typedef ChannelPost = Post;

Post toggleCurrentUserReaction(
  Post post,
  String emojiName, {
  String currentUserId = '',
}) {
  final int index = post.reactions.indexWhere(
    (PostReaction reaction) => reaction.emojiName == emojiName,
  );
  if (index < 0) {
    return post.withReactions(<PostReaction>[
      ...post.reactions,
      PostReaction(
        emoji: mattermostSystemEmojis[emojiName] ?? ':$emojiName:',
        emojiName: emojiName,
        count: 1,
        reactedByCurrentUser: true,
        userIds: currentUserId.isEmpty
            ? const <String>[]
            : <String>[currentUserId],
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
        userIds: reaction.userIds
            .where((String userId) => userId != currentUserId)
            .toList(growable: false),
      );
    }
  } else {
    reactions[index] = reaction.copyWith(
      count: reaction.count + 1,
      reactedByCurrentUser: true,
      userIds: currentUserId.isEmpty || reaction.userIds.contains(currentUserId)
          ? reaction.userIds
          : <String>[...reaction.userIds, currentUserId],
    );
  }
  return post.withReactions(reactions);
}

/// Applies one server-confirmed reaction delta without changing post content.
///
/// WebSocket delivery can overlap an optimistic local mutation, so adding an
/// existing user and removing an absent user are intentionally idempotent.
Post applyRealtimeReaction(
  Post post, {
  required String emojiName,
  required String userId,
  required bool added,
  required String currentUserId,
}) {
  if (emojiName.isEmpty || userId.isEmpty) return post;
  final int index = post.reactions.indexWhere(
    (PostReaction reaction) => reaction.emojiName == emojiName,
  );
  if (added) {
    if (index < 0) {
      return post.withReactions(<PostReaction>[
        ...post.reactions,
        PostReaction(
          emoji: mattermostSystemEmojis[emojiName] ?? ':$emojiName:',
          emojiName: emojiName,
          count: 1,
          reactedByCurrentUser: userId == currentUserId,
          userIds: <String>[userId],
        ),
      ]);
    }
    final PostReaction current = post.reactions[index];
    if (current.userIds.contains(userId)) return post;
    final List<PostReaction> reactions = List<PostReaction>.of(post.reactions);
    final List<String> userIds = <String>[...current.userIds, userId];
    reactions[index] = current.copyWith(
      count: userIds.length,
      reactedByCurrentUser:
          current.reactedByCurrentUser || userId == currentUserId,
      userIds: userIds,
    );
    return post.withReactions(reactions);
  }

  if (index < 0) return post;
  final PostReaction current = post.reactions[index];
  if (!current.userIds.contains(userId)) return post;
  final List<String> userIds = current.userIds
      .where((String candidate) => candidate != userId)
      .toList(growable: false);
  final List<PostReaction> reactions = List<PostReaction>.of(post.reactions);
  if (userIds.isEmpty) {
    reactions.removeAt(index);
  } else {
    reactions[index] = current.copyWith(
      count: userIds.length,
      reactedByCurrentUser:
          current.reactedByCurrentUser && userId != currentUserId,
      userIds: userIds,
    );
  }
  return post.withReactions(reactions);
}

int compareMessagesBySentAt(Post first, Post second) {
  final int byTime = first.sentAt.compareTo(second.sentAt);
  return byTime != 0 ? byTime : first.id.compareTo(second.id);
}
