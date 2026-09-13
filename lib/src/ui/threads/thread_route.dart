import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';

/// Ephemeral presentation data for the full-screen thread route.
///
/// Thread contents remain network-first and live in [ThreadPane]'s provider;
/// these values only describe how the caller should be updated while it is open.
final class ThreadRouteArguments {
  const ThreadRouteArguments({
    required this.rootPostId,
    required this.channel,
    this.highlightedPostId,
    this.serverUrl,
    this.teamId,
    this.unreadReplies = 0,
    this.positionAtEndWhenRead = false,
    this.onSelectChannel,
    this.onReplySent,
    this.onThreadRead,
    this.onThreadUnfollowed,
  });

  final String rootPostId;
  final SidebarChannel channel;
  final String? highlightedPostId;
  final Uri? serverUrl;
  final String? teamId;
  final int unreadReplies;
  final bool positionAtEndWhenRead;
  final ValueChanged<String>? onSelectChannel;
  final ValueChanged<ChannelPost>? onReplySent;
  final ValueChanged<DateTime>? onThreadRead;
  final ValueChanged<String>? onThreadUnfollowed;
}

abstract final class ThreadRoute {
  static const String name = 'thread';
  static const String path = '/thread/:rootPostId';

  static Future<void> open(
    BuildContext context,
    ThreadRouteArguments arguments,
  ) => context.push<void>(location(arguments.rootPostId), extra: arguments);

  static String location(String rootPostId) =>
      '/thread/${Uri.encodeComponent(rootPostId)}';
}
