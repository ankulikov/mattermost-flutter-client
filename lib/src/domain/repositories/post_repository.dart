import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/page.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';

export '../models/page.dart';
export '../models/post.dart';

sealed class PostRealtimeEvent {
  const PostRealtimeEvent();
}

/// A newly created or edited post from the active session's shared event bus.
final class PostRealtimeUpserted extends PostRealtimeEvent {
  const PostRealtimeUpserted(this.post);

  final ChannelPost post;
}

/// A server-confirmed deletion. The deleted projection retains thread context.
final class PostRealtimeDeleted extends PostRealtimeEvent {
  const PostRealtimeDeleted(this.post);

  final ChannelPost post;
}

/// The socket reconnected or skipped sequence numbers, so REST must reconcile.
final class PostRealtimeRecoveryRequired extends PostRealtimeEvent {
  const PostRealtimeRecoveryRequired();
}

/// Owns channel post pages, creation and reaction commands.
abstract class PostRepository {
  const PostRepository();

  /// Watches post mutations for one open channel.
  ///
  /// Cancelling the returned subscription releases only this feature's
  /// interest; the authenticated session continues owning the shared socket.
  Stream<PostRealtimeEvent> watchRealtime({
    required AuthSession session,
    String channelId = '',
    String rootPostId = '',
  }) => const Stream<PostRealtimeEvent>.empty();

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

  Future<ChannelPost> sendPost({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
    List<String> fileIds = const <String>[],
  }) {
    if (fileIds.isNotEmpty) {
      throw UnimplementedError('This post repository does not support files');
    }
    return sendText(
      session: session,
      channelId: channelId,
      message: message,
      pendingPostId: pendingPostId,
      rootPostId: rootPostId,
    );
  }

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
