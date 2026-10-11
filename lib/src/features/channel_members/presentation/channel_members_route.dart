import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';

final class ChannelMembersRouteArguments {
  const ChannelMembersRouteArguments({required this.channel});

  final SidebarChannel channel;
}

abstract final class ChannelMembersRoute {
  static const String name = 'channel-members';
  static const String path = '/channel/:channelId/members';

  static Future<void> open(
    BuildContext context,
    ChannelMembersRouteArguments arguments,
  ) => context.push<void>(location(arguments.channel.id), extra: arguments);

  static String location(String channelId) =>
      '/channel/${Uri.encodeComponent(channelId)}/members';
}
