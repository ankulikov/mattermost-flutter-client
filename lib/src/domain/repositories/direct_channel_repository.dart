import 'package:mattermost_flutter/src/domain/models/channel.dart';

abstract interface class DirectChannelRepository {
  Future<SidebarChannel> open({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  });
}
