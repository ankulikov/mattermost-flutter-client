import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';

/// Ephemeral presentation data for a chat opened from Inbox.
final class InboxChannelRouteArguments {
  const InboxChannelRouteArguments({
    required this.channel,
    this.onSelectChannel,
  });

  final SidebarChannel channel;
  final ValueChanged<String>? onSelectChannel;
}

/// Keeps a compact Inbox chat on top of the Inbox navigation context.
abstract final class InboxChannelRoute {
  static const String name = 'inbox-channel';
  static const String path = '/inbox/channel/:channelId';

  static Future<void> open(
    BuildContext context,
    InboxChannelRouteArguments arguments,
  ) => context.push<void>(location(arguments.channel.id), extra: arguments);

  static String location(String channelId) =>
      '/inbox/channel/${Uri.encodeComponent(channelId)}';

  static Widget build(BuildContext context, InboxChannelRouteArguments args) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ChannelPostsPane(
          key: ValueKey<String>('inbox-channel-${args.channel.id}'),
          channel: args.channel,
          onBack: context.pop,
          onSelectChannel: args.onSelectChannel == null
              ? null
              : (String name) {
                  args.onSelectChannel!(name);
                  if (context.mounted) context.pop();
                },
        ),
      ),
    );
  }
}
