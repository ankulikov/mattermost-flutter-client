import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

abstract interface class DirectChannelRepository {
  Future<SidebarChannel> open({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  });
}
