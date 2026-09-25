import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/ui/messages/post_action_navigation.dart';
import 'package:mattermost_flutter/src/ui/messages/rich_attachment_strings.dart';

void main() {
  testWidgets('routes an action permalink inside the app', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                handlePostActionGotoLocation(
                  context,
                  serverUrl: Uri.parse('https://chat.example.test'),
                  location: '/team/pl/post-42',
                ),
              ),
              child: const Text('Open result'),
            ),
          ),
        ),
        GoRoute(
          path: '/post/:postId',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: Text('Post ${state.pathParameters['postId']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('Open result'));
    await tester.pumpAndSettle();

    expect(find.text('Post post-42'), findsOneWidget);
  });

  testWidgets('rejects an unknown action destination scheme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => unawaited(
                handlePostActionGotoLocation(
                  context,
                  serverUrl: Uri.parse('https://chat.example.test'),
                  location: 'javascript:alert(1)',
                ),
              ),
              child: const Text('Open unsafe result'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open unsafe result'));
    await tester.pump();

    expect(find.text(RichAttachmentStrings.navigationFailed), findsOneWidget);
  });
}
