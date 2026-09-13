import 'package:mattermost_flutter/src/domain/models/post.dart';

final class ChannelReplySummary {
  const ChannelReplySummary({
    this.replyIds = const <String>{},
    this.lastReplyAt,
  });

  final Set<String> replyIds;
  final DateTime? lastReplyAt;
}

final class ChannelPostPage {
  const ChannelPostPage({
    this.posts = const <ChannelPost>[],
    this.replySummaries = const <String, ChannelReplySummary>{},
    this.beforePostId,
    this.afterPostId,
    this.hasOlder = false,
    this.hasNewer = false,
  });

  final List<ChannelPost> posts;
  final Map<String, ChannelReplySummary> replySummaries;
  final String? beforePostId;
  final String? afterPostId;
  final bool hasOlder;
  final bool hasNewer;
}
