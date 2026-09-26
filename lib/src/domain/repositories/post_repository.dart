import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/page.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';

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

  /// Resolves the channel/thread metadata needed to handle a post permalink.
  Future<PostNavigationTarget> resolveNavigationTarget({
    required AuthSession session,
    required String postId,
  }) => throw UnimplementedError();

  /// Loads a bounded channel window on both sides of [postId].
  Future<ChannelPostPage> loadAround({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) => throw UnimplementedError();

  /// Loads posts newer than [afterPostId] while viewing a historical window.
  Future<ChannelPostPage> loadNewer({
    required AuthSession session,
    required String channelId,
    required String afterPostId,
  }) => throw UnimplementedError();

  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) => throw UnimplementedError();

  /// Deletes a post. Presentation owns removing it from its volatile snapshot
  /// after this command succeeds.
  Future<void> deletePost({
    required AuthSession session,
    required String postId,
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
