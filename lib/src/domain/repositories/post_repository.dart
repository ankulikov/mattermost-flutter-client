import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/page.dart';

export '../models/page.dart';
export '../models/post.dart';

/// Transitional contract for loading pages in the channel-post scenario.
///
/// It remains separate from send and reaction contracts until the post
/// repository migration consolidates those operations behind one aggregate API.
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
