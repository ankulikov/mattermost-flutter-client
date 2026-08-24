import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

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
    this.hasOlder = false,
  });

  final List<ChannelPost> posts;
  final Map<String, ChannelReplySummary> replySummaries;
  final String? beforePostId;
  final bool hasOlder;
}

abstract interface class ChannelPostRepository {
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  });

  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  });
}
