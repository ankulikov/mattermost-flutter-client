import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/page.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';

export '../models/page.dart';
export '../models/post.dart';

/// Owns channel post pages, creation and reaction commands.
abstract class PostRepository {
  const PostRepository();

  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  });

  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  });

  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) => throw UnimplementedError();

  Future<void> addReaction({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) => throw UnimplementedError();

  Future<void> removeReaction({
    required AuthSession session,
    required String postId,
    required String emojiName,
  }) => throw UnimplementedError();
}
