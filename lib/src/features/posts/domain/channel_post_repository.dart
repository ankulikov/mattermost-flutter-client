import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';

abstract interface class ChannelPostRepository {
  Future<List<ChannelPost>> loadHistory(String channelId);
}
