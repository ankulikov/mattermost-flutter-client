import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

List<ChannelPost> mapMattermostPosts({
  required Iterable<MattermostPostDto> posts,
  required Iterable<MattermostUserDto> users,
  required String currentUserId,
  bool includeDeleted = false,
}) {
  final Map<String, String> authorNames = <String, String>{
    for (final MattermostUserDto user in users)
      user.id: mattermostUserDisplayName(user),
  };
  return posts
      .where((MattermostPostDto post) => includeDeleted || post.deleteAt == 0)
      .map(
        (MattermostPostDto post) => ChannelPost(
          id: post.id,
          channelId: post.channelId,
          author: PostAuthor(
            id: post.userId,
            displayName: authorNames[post.userId] ?? post.userId,
          ),
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

String mattermostUserDisplayName(MattermostUserDto user) {
  final String fullName = '${user.firstName} ${user.lastName}'.trim();
  if (fullName.isNotEmpty) return fullName;
  if (user.nickname.isNotEmpty) return user.nickname;
  return user.username.isEmpty ? user.id : user.username;
}

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
