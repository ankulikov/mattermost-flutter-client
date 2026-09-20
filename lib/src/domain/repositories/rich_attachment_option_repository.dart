import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment_option.dart';

/// Searches server-owned values for legacy `users` and `channels` selects.
abstract interface class RichAttachmentOptionRepository {
  Future<List<RichAttachmentSystemOption>> search({
    required AuthSession session,
    required RichAttachmentSelectDataSource dataSource,
    required String query,
    int limit = 30,
  });
}
