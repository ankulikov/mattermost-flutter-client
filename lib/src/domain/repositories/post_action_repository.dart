import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';

/// Executes an attachment action and returns Mattermost's authoritative post.
abstract interface class PostActionRepository {
  Future<PostActionResult> execute({
    required AuthSession session,
    required String postId,
    required String actionId,
    RichAttachmentActionToken? token,
    String? selectedOption,
  });
}
