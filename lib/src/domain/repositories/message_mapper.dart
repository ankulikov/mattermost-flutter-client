import 'package:mattermost_flutter/src/domain/models/post.dart';

/// Public domain contract for mapping a wire/source representation to messages.
///
/// Source types stay generic so the contract never imports API DTOs.
abstract interface class MessageMapper<SourceMessage, SourceUser> {
  List<ChannelPost> map({
    required Iterable<SourceMessage> posts,
    required Iterable<SourceUser> users,
    required String currentUserId,
    bool includeDeleted = false,
  });
}
