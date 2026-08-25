import 'package:mattermost_flutter/src/features/messages/domain/message.dart';

final class FollowedThread {
  const FollowedThread({
    required this.root,
    required this.replyCount,
    required this.lastReplyAt,
    required this.lastViewedAt,
    required this.unreadReplies,
    required this.unreadMentions,
    this.participants = const <PostAuthor>[],
  });

  final ChannelPost root;
  final int replyCount;
  final DateTime lastReplyAt;
  final DateTime lastViewedAt;
  final int unreadReplies;
  final int unreadMentions;
  final List<PostAuthor> participants;

  String get id => root.id;
  String get channelId => root.channelId;
  bool get isUnread => unreadReplies > 0;
}

final class FollowedThreadsPage {
  const FollowedThreadsPage({
    required this.items,
    required this.total,
    required this.totalUnreadThreads,
    required this.totalUnreadMentions,
  });

  final List<FollowedThread> items;
  final int total;
  final int totalUnreadThreads;
  final int totalUnreadMentions;
}
