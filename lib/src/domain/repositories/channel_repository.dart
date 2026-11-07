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

abstract interface class ChannelSidebarCategoryRepository {
  Future<void> setCategoryCollapsed({
    required AuthSession session,
    required String teamId,
    required String categoryId,
    required bool collapsed,
  });
}

abstract interface class ChannelSidebarActionsRepository {
  Future<List<SidebarSection>> getMovableCategories(
    AuthSession session,
    String teamId,
  );

  Future<void> markChannelUnread(AuthSession session, String channelId);

  Future<void> setChannelFavorite(
    AuthSession session,
    String teamId,
    SidebarChannel channel,
    bool favorite,
  );

  Future<void> setChannelMuted(
    AuthSession session,
    String channelId,
    bool muted,
  );

  Future<void> moveChannelToCategory(
    AuthSession session,
    String teamId,
    String channelId,
    String categoryId,
  );

  Future<void> closeConversation(AuthSession session, SidebarChannel channel);

  Future<void> leaveChannel(AuthSession session, SidebarChannel channel);
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
    this.mentionsCurrentUser = false,
  });

  final String channelId;
  final bool isThreadReply;
  final bool mentionsCurrentUser;
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
