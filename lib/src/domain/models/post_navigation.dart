import 'package:mattermost_flutter/src/domain/models/channel.dart';

/// Resolved destination of a Mattermost post permalink.
final class PostNavigationTarget {
  const PostNavigationTarget({
    required this.linkedPostId,
    required this.channelPostId,
    required this.channel,
    this.threadRootPostId,
    this.threadHighlightedPostId,
  });

  /// Post ID encoded in the permalink.
  final String linkedPostId;

  /// Root post that is visible in the channel timeline.
  final String channelPostId;

  final SidebarChannel channel;

  /// Thread to open when the target is a reply or a root with replies.
  final String? threadRootPostId;

  /// Reply to reveal and highlight inside the thread.
  final String? threadHighlightedPostId;
}
