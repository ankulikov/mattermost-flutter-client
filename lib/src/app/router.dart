import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_channel_route.dart';
import 'package:mattermost_flutter/src/ui/shell/shell_page.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const BootstrapPage(),
    ),
    GoRoute(
      name: InboxChannelRoute.name,
      path: InboxChannelRoute.path,
      redirect: (BuildContext context, GoRouterState state) {
        final Object? extra = state.extra;
        final String? channelId = state.pathParameters['channelId'];
        if (extra is! InboxChannelRouteArguments ||
            channelId != extra.channel.id) {
          return '/';
        }
        return null;
      },
      pageBuilder: (BuildContext context, GoRouterState state) {
        final InboxChannelRouteArguments arguments =
            state.extra! as InboxChannelRouteArguments;
        return MaterialPage<void>(
          key: state.pageKey,
          child: InboxChannelRoute.build(context, arguments),
        );
      },
    ),
    GoRoute(
      name: ThreadRoute.name,
      path: ThreadRoute.path,
      redirect: (BuildContext context, GoRouterState state) {
        final Object? extra = state.extra;
        final String? rootPostId = state.pathParameters['rootPostId'];
        if (extra is! ThreadRouteArguments || rootPostId != extra.rootPostId) {
          return '/';
        }
        return null;
      },
      pageBuilder: (BuildContext context, GoRouterState state) {
        final ThreadRouteArguments arguments =
            state.extra! as ThreadRouteArguments;
        return MaterialPage<void>(
          key: state.pageKey,
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              child: ThreadPane(
                key: ValueKey<String>('thread-${arguments.rootPostId}'),
                rootPostId: arguments.rootPostId,
                channel: arguments.channel,
                serverUrl: arguments.serverUrl,
                teamId: arguments.teamId,
                unreadReplies: arguments.unreadReplies,
                positionAtEndWhenRead: arguments.positionAtEndWhenRead,
                onSelectChannel: arguments.onSelectChannel,
                onReplySent: arguments.onReplySent,
                onThreadRead: arguments.onThreadRead,
                onThreadUnfollowed: arguments.onThreadUnfollowed,
                onClose: context.pop,
              ),
            ),
          ),
        );
      },
    ),
  ],
);
