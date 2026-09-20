import 'package:mattermost_flutter/src/domain/models/post.dart';

/// Result of a server-mediated interactive post action.
final class PostActionResult {
  const PostActionResult({required this.updatedPost, this.gotoLocation = ''});

  final ChannelPost updatedPost;
  final String gotoLocation;
}

sealed class PostActionRealtimeEvent {
  const PostActionRealtimeEvent();
}

/// An authoritative post edit delivered after an action response.
final class PostActionPostUpdated extends PostActionRealtimeEvent {
  const PostActionPostUpdated(this.post);

  final ChannelPost post;
}

/// Volatile text emitted by Mattermost for an integration action.
final class PostActionEphemeralFeedback extends PostActionRealtimeEvent {
  const PostActionEphemeralFeedback({
    required this.channelId,
    required this.sourceRootPostId,
    required this.message,
  });

  final String channelId;
  final String sourceRootPostId;
  final String message;
}
