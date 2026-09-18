import 'package:mattermost_flutter/src/domain/models/post.dart';

/// Result of a server-mediated interactive post action.
final class PostActionResult {
  const PostActionResult({required this.updatedPost, this.gotoLocation = ''});

  final ChannelPost updatedPost;
  final String gotoLocation;
}
