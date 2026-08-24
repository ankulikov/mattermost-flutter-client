import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

final class ChannelPostSnapshot {
  const ChannelPostSnapshot({
    this.posts = const <ChannelPost>[],
    this.hasOlder = true,
  });

  final List<ChannelPost> posts;
  final bool hasOlder;
}

final class ChannelPostRefreshResult {
  const ChannelPostRefreshResult({required this.newPostIds});

  final Set<String> newPostIds;
}

abstract interface class ChannelPostRepository {
  Stream<ChannelPostSnapshot> watch({
    required String accountId,
    required String channelId,
  });

  Future<ChannelPostSnapshot> read({
    required String accountId,
    required String channelId,
  });

  Future<ChannelPostRefreshResult> refreshLatest({
    required AuthSession session,
    required String channelId,
  });

  Future<void> loadOlder({
    required AuthSession session,
    required String channelId,
  });
}
