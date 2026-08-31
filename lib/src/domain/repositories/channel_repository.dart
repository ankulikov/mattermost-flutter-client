import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';

/// Owns channel navigation and direct-message channel operations.
abstract interface class ChannelRepository {
  Future<ChannelSidebarSnapshot> load(AuthSession session);

  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  });
}
