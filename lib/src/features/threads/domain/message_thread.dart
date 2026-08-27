import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

final class MessageThread {
  const MessageThread({
    required this.rootPostId,
    this.root,
    this.replies = const <ChannelPost>[],
    this.isComplete = false,
    this.loadedAt,
  });

  final String rootPostId;
  final ChannelPost? root;
  final List<ChannelPost> replies;
  final bool isComplete;
  final DateTime? loadedAt;
}
