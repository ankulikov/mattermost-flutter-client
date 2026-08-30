import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';

abstract interface class ChannelSidebarRepository {
  Future<ChannelSidebarSnapshot> load(AuthSession session);
}
