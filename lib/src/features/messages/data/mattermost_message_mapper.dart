import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message.dart';
import 'package:mattermost_flutter/src/features/messages/domain/message_mapper.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_display_name.dart';

final class MattermostMessageMapper
    implements MessageMapper<MattermostPostDto, MattermostUserDto> {
  const MattermostMessageMapper();

  @override
  List<ChannelPost> map({
    required Iterable<MattermostPostDto> posts,
    required Iterable<MattermostUserDto> users,
    required String currentUserId,
    bool includeDeleted = false,
  }) {
    final Map<String, MattermostUserDto> authors = <String, MattermostUserDto>{
      for (final MattermostUserDto user in users) user.id: user,
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

PostAuthor _mapAuthor(String userId, MattermostUserDto? user) => PostAuthor(
  id: userId,
  displayName: user == null ? userId : _displayName(user),
  profileImageUpdatedAt: user?.profileImageUpdatedAt ?? 0,
);

String _displayName(MattermostUserDto user) => resolveUserDisplayName(
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
          count: entry.value.length,
          reactedByCurrentUser: entry.value.any(
            (MattermostReactionDto reaction) =>
                reaction.userId == currentUserId,
          ),
        ),
      )
      .toList(growable: false);
}

String _emojiLabel(String name) => switch (name) {
  '+1' || 'thumbsup' => '👍',
  'heart' => '❤️',
  'tada' => '🎉',
  _ => ':$name:',
};
