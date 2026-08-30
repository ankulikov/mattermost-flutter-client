import 'package:markdown/markdown.dart' as md;
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/policies/user_display_name.dart';
import 'package:mattermost_flutter/src/features/emojis/domain/custom_emoji.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';

final class MattermostMessageMapper
    implements MessageMapper<MattermostPostDto, UserSummary> {
  const MattermostMessageMapper();

  @override
  List<ChannelPost> map({
    required Iterable<MattermostPostDto> posts,
    required Iterable<UserSummary> users,
    required String currentUserId,
    bool includeDeleted = false,
  }) {
    final Map<String, UserSummary> authors = <String, UserSummary>{
      for (final UserSummary user in users) user.id: user,
    };
    return posts
        .where((MattermostPostDto post) => includeDeleted || post.deleteAt == 0)
        .map(
          (MattermostPostDto post) => ChannelPost(
            id: post.id,
            channelId: post.channelId,
            author: _mapAuthor(post.userId, authors[post.userId]),
            sentAt: DateTime.fromMillisecondsSinceEpoch(post.createAt),
            message: post.deleteAt == 0 ? post.message : '',
            customEmojis: post.deleteAt == 0
                ? (post.metadata?.emojis ?? const <MattermostEmojiDto>[])
                      .where(
                        (MattermostEmojiDto emoji) =>
                            emoji.name.isNotEmpty && emoji.deleteAt == 0,
                      )
                      .map(
                        (MattermostEmojiDto emoji) => CustomEmojiReference(
                          name: emoji.name,
                          id: emoji.id,
                          updatedAt: emoji.updateAt,
                        ),
                      )
                      .toList(growable: false)
                : const <CustomEmojiReference>[],
            attachments: post.deleteAt == 0
                ? (post.metadata?.files ?? const <MattermostFileInfoDto>[])
                      .where(
                        (MattermostFileInfoDto file) =>
                            file.id.isNotEmpty && file.deleteAt == 0,
                      )
                      .map(
                        (MattermostFileInfoDto file) => PostAttachment(
                          id: file.id,
                          name: file.name,
                          size: file.size,
                          mimeType: file.mimeType,
                          extension: file.extension,
                          width: file.width,
                          height: file.height,
                          hasPreviewImage: file.hasPreviewImage,
                        ),
                      )
                      .toList(growable: false)
                : const <PostAttachment>[],
            rootId: post.rootId,
            replyCount: post.replyCount,
            isDeleted: post.deleteAt != 0,
            lastReplyAt: post.lastReplyAt == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(post.lastReplyAt),
            reactions: post.deleteAt == 0
                ? _mapReactions(post, currentUserId)
                : const <PostReaction>[],
          ),
        )
        .toList(growable: false);
  }
}

PostAuthor _mapAuthor(String userId, UserSummary? user) => PostAuthor(
  id: userId,
  displayName: user == null ? userId : _displayName(user),
  profileImageUpdatedAt: user?.profileImageUpdatedAt ?? 0,
);

String _displayName(UserSummary user) => resolveUserDisplayName(
  id: user.id,
  username: user.username,
  nickname: user.nickname,
  firstName: user.firstName,
  lastName: user.lastName,
);

List<PostReaction> _mapReactions(MattermostPostDto post, String currentUserId) {
  final Map<String, List<MattermostReactionDto>> grouped =
      <String, List<MattermostReactionDto>>{};
  for (final MattermostReactionDto reaction
      in post.metadata?.reactions ?? const <MattermostReactionDto>[]) {
    grouped
        .putIfAbsent(reaction.emojiName, () => <MattermostReactionDto>[])
        .add(reaction);
  }
  return grouped.entries
      .map(
        (MapEntry<String, List<MattermostReactionDto>> entry) => PostReaction(
          emoji: _emojiLabel(entry.key),
          emojiName: entry.key,
          count: entry.value.length,
          reactedByCurrentUser: entry.value.any(
            (MattermostReactionDto reaction) =>
                reaction.userId == currentUserId,
          ),
        ),
      )
      .toList(growable: false);
}

String _emojiLabel(String name) => md.emojis[name] ?? ':$name:';
