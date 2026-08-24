import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';

abstract interface class ChannelSidebarRepository {
  Future<ChannelSidebarSnapshot> load(AuthSession session);
}
