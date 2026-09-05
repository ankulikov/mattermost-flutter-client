import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_thread_host.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  const SidebarChannel publicChannel = SidebarChannel(
    id: 'town-square',
    teamId: 'team',
    name: 'town-square',
    displayName: 'Town Square',
    kind: ChannelKind.publicChannel,
  );
  const SidebarChannel directChannel = SidebarChannel(
    id: 'direct-channel',
    teamId: 'team',
    name: 'direct-channel',
    displayName: 'Ada Lovelace',
    kind: ChannelKind.directMessage,
  );

  group('InboxThreadTarget', () {
    test('opens a channel reply at its root thread', () {
      final InboxThreadTarget target = InboxThreadTarget.fromItem(
        ChannelPostInboxItem(
          candidate: _candidate(
            _post(id: 'reply', channelId: publicChannel.id, rootId: 'root'),
            publicChannel,
          ),
        ),
      );

      expect(target.rootPostId, 'root');
      expect(target.channel, same(publicChannel));
    });

    test('opens a direct-message bundle at its latest message thread', () {
      final InboxThreadTarget target = InboxThreadTarget.fromItem(
        DirectMessageBundleInboxItem(
          channelId: directChannel.id,
          authorId: 'ada',
          automationClass: InboxAutomationClass.person,
          messages: <InboxPostCandidate>[
            _candidate(
              _post(id: 'first', channelId: directChannel.id),
              directChannel,
            ),
            _candidate(
              _post(
                id: 'latest-reply',
                channelId: directChannel.id,
                rootId: 'direct-root',
              ),
              directChannel,
            ),
          ],
        ),
      );

      expect(target.rootPostId, 'direct-root');
      expect(target.channel.kind, ChannelKind.directMessage);
    });

    test('preserves unread context for a followed thread', () {
      final FollowedThread thread = FollowedThread(
        root: _post(id: 'thread-root', channelId: publicChannel.id),
        replyCount: 3,
        lastReplyAt: DateTime.utc(2026, 9, 4, 12),
        lastViewedAt: DateTime.utc(2026, 9, 4, 11),
        unreadReplies: 2,
        unreadMentions: 1,
      );
      final InboxThreadTarget target = InboxThreadTarget.fromItem(
        ThreadInboxItem(thread: thread, channel: publicChannel, teamId: 'team'),
      );

      expect(target.rootPostId, 'thread-root');
      expect(target.unreadReplies, 2);
      expect(target.positionAtEndWhenRead, isFalse);
    });
  });

  testWidgets('opens a thread beside Inbox when width allows two panes', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final InboxItem item = ChannelPostInboxItem(
      candidate: _candidate(
        _post(id: 'channel-root', channelId: publicChannel.id),
        publicChannel,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
        ],
        child: MaterialApp(
          home: InboxThreadHost(
            showAdjacentThread: true,
            background: const Center(child: Text('Current workspace')),
            inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
              child: FilledButton(
                onPressed: () => onOpenItem(item),
                child: const Text('Inbox message'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.text('Current workspace'), findsOneWidget);

    await tester.tap(find.text('Inbox message'));
    await tester.pump();

    expect(find.text('Inbox message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('inbox-thread-channel-root')),
      findsOneWidget,
    );
    expect(find.text('Current workspace'), findsNothing);

    await tester.tap(find.byTooltip('Close thread'));
    await tester.pump();

    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.text('Current workspace'), findsOneWidget);
  });

  testWidgets('pushes a thread on narrow width and Back restores Inbox', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final InboxItem item = DirectMessageBundleInboxItem(
      channelId: directChannel.id,
      authorId: 'ada',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[
        _candidate(
          _post(id: 'direct-message', channelId: directChannel.id),
          directChannel,
        ),
      ],
    );
    late final GoRouter router;
    router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => InboxThreadHost(
            showAdjacentThread: false,
            background: const Text('Current workspace'),
            inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
              child: FilledButton(
                onPressed: () => onOpenItem(item),
                child: const Text('Direct message'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: ThreadRoute.path,
          builder: (_, GoRouterState state) =>
              Text('Route thread ${state.pathParameters['rootPostId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Direct message'));
    await tester.pumpAndSettle();

    expect(find.text('Route thread direct-message'), findsOneWidget);
    expect(find.text('Direct message'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Direct message'), findsOneWidget);
    expect(find.text('Route thread direct-message'), findsNothing);
  });
}

InboxPostCandidate _candidate(Post post, SidebarChannel channel) =>
    InboxPostCandidate(
      post: post,
      channel: channel,
      reason: InboxAttentionReason.directMention,
    );

Post _post({
  required String id,
  required String channelId,
  String rootId = '',
}) => Post(
  id: id,
  channelId: channelId,
  author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
  sentAt: DateTime.utc(2026, 9, 4, 12),
  message: id,
  rootId: rootId,
);

final class _NoopAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> authenticateWithPassword({
    required Uri serverUrl,
    required String loginId,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthenticationMethods> discoverAuthenticationMethods({
    required Uri serverUrl,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSessionToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> authenticateWithSso({
    required Uri serverUrl,
    required SsoProvider provider,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelSsoAuthentication() async {}

  @override
  Future<List<SsoOption>> discoverSsoOptions({required Uri serverUrl}) async =>
      const <SsoOption>[];

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}
