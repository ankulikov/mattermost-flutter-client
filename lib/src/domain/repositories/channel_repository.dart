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

/// Optional realtime capability for a channel sidebar repository.
///
/// Keeping this separate from [ChannelRepository] leaves simple/offline
/// implementations source-compatible while the production repository can
/// provide session-owned WebSocket updates and server read acknowledgements.
abstract interface class ChannelSidebarRealtimeRepository {
  Stream<ChannelSidebarRealtimeEvent> watchSidebar({
    required AuthSession session,
  });

  Future<void> markChannelViewed({
    required AuthSession session,
    required String channelId,
    String? previousChannelId,
  });
}

sealed class ChannelSidebarRealtimeEvent {
  const ChannelSidebarRealtimeEvent();
}

/// A new post which may change the containing channel's unread treatment.
final class ChannelSidebarMessagePosted extends ChannelSidebarRealtimeEvent {
  const ChannelSidebarMessagePosted({
    required this.channelId,
    required this.isThreadReply,
  });

  final String channelId;
  final bool isThreadReply;
}

/// An authoritative read/unread transition broadcast by Mattermost.
final class ChannelSidebarUnreadChanged extends ChannelSidebarRealtimeEvent {
  const ChannelSidebarUnreadChanged({
    required this.channelId,
    required this.isUnread,
  });

  final String channelId;
  final bool isUnread;
}

/// The volatile sidebar snapshot must be reconciled from REST.
final class ChannelSidebarRefreshRequired extends ChannelSidebarRealtimeEvent {
  const ChannelSidebarRefreshRequired();
}
