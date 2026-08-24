import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

final class ChannelPostPage {
  const ChannelPostPage({
    this.posts = const <ChannelPost>[],
    this.beforePostId,
    this.hasOlder = false,
  });

  final List<ChannelPost> posts;
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
