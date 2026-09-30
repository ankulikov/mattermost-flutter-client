import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/viewed_channel_posts.dart';

abstract class ViewedChannelPostsRepository {
  const ViewedChannelPostsRepository();

  Future<ViewedChannelPostsSnapshot> load({required AuthSession session});

  /// Adds one post id to the channel's content-free viewed set.
  Future<void> add({
    required AuthSession session,
    required String channelId,
    required String postId,
  });

  /// Deletes the channel's viewed-post preference after its read boundary moves.
  Future<void> removeChannel({
    required AuthSession session,
    required String channelId,
  });
}
