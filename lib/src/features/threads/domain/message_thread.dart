import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

final class MessageThread {
  const MessageThread({
    required this.rootPostId,
    this.root,
    this.replies = const <ChannelPost>[],
    this.isComplete = false,
  });

  final String rootPostId;
  final ChannelPost? root;
  final List<ChannelPost> replies;
  final bool isComplete;
}
