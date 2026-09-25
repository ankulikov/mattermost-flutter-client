import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/linked_post_page.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('wide root permalink shows the target channel and Back pops it', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 900));
    final GoRouter router = _router(_rootTarget);
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(router));
    router.push('/linked');
    await tester.pumpAndSettle();

    expect(find.byType(ChannelPostsPane), findsOneWidget);
    expect(find.byType(ThreadPane), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Source page'), findsOneWidget);
  });

  testWidgets(
    'compact root permalink shows the target channel and Back pops it',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(799, 900));
      final GoRouter router = _router(_rootTarget);
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      router.push('/linked');
      await tester.pumpAndSettle();

      expect(find.byType(ChannelPostsPane), findsOneWidget);
      expect(find.byType(ThreadPane), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Source page'), findsOneWidget);
    },
  );

  testWidgets(
    'compact threaded permalink opens only a thread and Close pops it',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(799, 900));
      final GoRouter router = _router(_replyTarget);
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      router.push('/linked');
      await tester.pumpAndSettle();

      expect(find.byType(ThreadPane), findsOneWidget);
      expect(find.byType(ChannelPostsPane), findsNothing);

      await tester.tap(find.byTooltip(ThreadStrings.close));
      await tester.pumpAndSettle();

      expect(find.text('Source page'), findsOneWidget);
    },
  );
}

Widget _app(GoRouter router) => ProviderScope(
  overrides: [authSessionProvider.overrideWithValue(null)],
  child: MaterialApp.router(routerConfig: router),
);

GoRouter _router(PostNavigationTarget target) => GoRouter(
  initialLocation: '/source',
  routes: <RouteBase>[
    GoRoute(
      path: '/source',
      builder: (BuildContext context, GoRouterState state) =>
          const Scaffold(body: Center(child: Text('Source page'))),
    ),
    GoRoute(
      path: '/linked',
      builder: (BuildContext context, GoRouterState state) =>
          LinkedPostPage(target: target),
    ),
  ],
);

const SidebarChannel _channel = SidebarChannel(
  id: 'channel-id',
  teamId: 'team-id',
  name: 'town-square',
  displayName: 'Town Square',
  kind: ChannelKind.publicChannel,
);

const PostNavigationTarget _rootTarget = PostNavigationTarget(
  linkedPostId: 'linked-root',
  channelPostId: 'linked-root',
  channel: _channel,
);

const PostNavigationTarget _replyTarget = PostNavigationTarget(
  linkedPostId: 'linked-reply',
  channelPostId: 'thread-root',
  channel: _channel,
  threadRootPostId: 'thread-root',
  threadHighlightedPostId: 'linked-reply',
);
