import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_channel_route.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_thread_host.dart';
import 'package:mattermost_flutter/src/ui/posts/post_permalink_route.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/threads/thread_route.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
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
    test('rejects channel posts so they use permalink navigation', () {
      expect(
        () => InboxThreadTarget.fromItem(
          ChannelPostInboxItem(
            candidate: _candidate(
              _post(id: 'reply', channelId: publicChannel.id, rootId: 'root'),
              publicChannel,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('opens a single direct message at its root thread', () {
      final InboxThreadTarget target = InboxThreadTarget.fromItem(
        DirectMessageBundleInboxItem(
          channelId: directChannel.id,
          authorId: 'ada',
          automationClass: InboxAutomationClass.person,
          messages: <InboxPostCandidate>[
            _candidate(
              _post(
                id: 'direct-reply',
                channelId: directChannel.id,
                rootId: 'direct-root',
              ),
              directChannel,
            ),
          ],
        ),
      );

      expect(target.rootPostId, 'direct-root');
      expect(target.channel, same(directChannel));
    });

    test('rejects a multi-message bundle as a thread target', () {
      final DirectMessageBundleInboxItem item = DirectMessageBundleInboxItem(
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
      );

      expect(() => InboxThreadTarget.fromItem(item), throwsArgumentError);
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

  testWidgets('opens a channel root beside Inbox through its permalink', (
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
          authSessionProvider.overrideWithValue(_session),
          postRepositoryProvider.overrideWithValue(
            _PostRepository(
              navigationTarget: const PostNavigationTarget(
                linkedPostId: 'channel-root',
                channelPostId: 'channel-root',
                channel: publicChannel,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: InboxThreadHost(
            showAdjacentWorkspace: true,
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
    await tester.pumpAndSettle();

    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.text('Current workspace'), findsOneWidget);

    await tester.tap(find.text('Inbox message'));
    await tester.pumpAndSettle();

    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.byType(ChannelPostsPane), findsOneWidget);
    expect(find.byType(ThreadPane), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('inbox-linked-post-channel-root')),
      findsOneWidget,
    );
    expect(find.text('Current workspace'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Inbox message'), findsOneWidget);
    expect(find.text('Current workspace'), findsOneWidget);
  });

  testWidgets(
    'opens a compact permalink and Back restores Inbox focus and scroll',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final InboxItem item = ChannelPostInboxItem(
        candidate: _candidate(
          _post(id: 'channel-message', channelId: publicChannel.id),
          publicChannel,
        ),
      );
      final FocusNode inboxFocus = FocusNode();
      final ScrollController inboxScroll = ScrollController();
      addTearDown(() {
        inboxFocus.dispose();
        inboxScroll.dispose();
      });
      late final GoRouter router;
      router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, _) => InboxThreadHost(
              showAdjacentWorkspace: false,
              background: const Text('Current workspace'),
              inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => ListView(
                controller: inboxScroll,
                children: <Widget>[
                  const SizedBox(height: 360),
                  Focus(
                    focusNode: inboxFocus,
                    child: FilledButton(
                      onPressed: () => onOpenItem(item),
                      child: const Text('Inbox channel root'),
                    ),
                  ),
                  const SizedBox(height: 720),
                ],
              ),
            ),
          ),
          GoRoute(
            path: PostPermalinkRoute.path,
            builder: (_, GoRouterState state) => PostPermalinkRoute(
              postId: state.pathParameters['postId']!,
              stateScopeId: 'compact-inbox-permalink',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
            authSessionProvider.overrideWithValue(_session),
            postRepositoryProvider.overrideWithValue(
              _PostRepository(
                navigationTarget: const PostNavigationTarget(
                  linkedPostId: 'channel-message',
                  channelPostId: 'channel-message',
                  channel: publicChannel,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      inboxScroll.jumpTo(240);
      await tester.pump();
      inboxFocus.requestFocus();
      await tester.pump();
      expect(inboxFocus.hasPrimaryFocus, isTrue);
      final double scrollOffset = inboxScroll.offset;

      await tester.tap(find.text('Inbox channel root'));
      await tester.pumpAndSettle();

      expect(find.byType(ChannelPostsPane), findsOneWidget);
      expect(find.text('Inbox channel root'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Inbox channel root'), findsOneWidget);
      expect(inboxScroll.offset, closeTo(scrollOffset, 0.1));
      expect(inboxFocus.hasPrimaryFocus, isTrue);
    },
  );

  testWidgets(
    'opens a channel reply at its authoritative root thread on wide width',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final InboxItem item = ChannelPostInboxItem(
        candidate: _candidate(
          _post(id: 'reply', channelId: publicChannel.id, rootId: 'root'),
          publicChannel,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
            authSessionProvider.overrideWithValue(_session),
            postRepositoryProvider.overrideWithValue(
              _PostRepository(
                navigationTarget: const PostNavigationTarget(
                  linkedPostId: 'reply',
                  channelPostId: 'root',
                  channel: publicChannel,
                  threadRootPostId: 'root',
                  threadHighlightedPostId: 'reply',
                ),
              ),
            ),
            threadRepositoryProvider.overrideWithValue(_ThreadRepository()),
          ],
          child: MaterialApp(
            home: InboxThreadHost(
              showAdjacentWorkspace: true,
              background: const Text('Current workspace'),
              inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
                child: FilledButton(
                  onPressed: () => onOpenItem(item),
                  child: const Text('Inbox reply'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Inbox reply'));
      await tester.pumpAndSettle();

      expect(find.text('Inbox reply'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('linked-post-thread-root')),
        findsOneWidget,
      );
      expect(find.byType(ChannelPostsPane), findsNothing);
      expect(find.text('Current workspace'), findsNothing);
    },
  );

  testWidgets('opens a multi-message bundle beside Inbox as a chat', (
    WidgetTester tester,
  ) async {
    final InboxItem item = DirectMessageBundleInboxItem(
      channelId: directChannel.id,
      authorId: 'ada',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[
        _candidate(
          _post(id: 'direct-message-1', channelId: directChannel.id),
          directChannel,
        ),
        _candidate(
          _post(id: 'direct-message-2', channelId: directChannel.id),
          directChannel,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
        ],
        child: MaterialApp(
          home: InboxThreadHost(
            showAdjacentWorkspace: true,
            background: const Text('Current workspace'),
            inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
              child: FilledButton(
                onPressed: () => onOpenItem(item),
                child: const Text('Direct message'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Direct message'));
    await tester.pump();

    expect(find.text('Direct message'), findsOneWidget);
    expect(find.byType(ChannelPostsPane), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('inbox-channel-direct-channel')),
      findsOneWidget,
    );
    expect(find.byType(ThreadPane), findsNothing);
  });

  testWidgets('keeps Inbox, DM chat, and its thread visible on wide width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1300, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final InboxItem item = DirectMessageBundleInboxItem(
      channelId: directChannel.id,
      authorId: 'ada',
      automationClass: InboxAutomationClass.person,
      messages: <InboxPostCandidate>[
        _candidate(
          _post(id: 'direct-message-1', channelId: directChannel.id),
          directChannel,
        ),
        _candidate(
          _post(id: 'direct-message-2', channelId: directChannel.id),
          directChannel,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
          authSessionProvider.overrideWithValue(_session),
          postRepositoryProvider.overrideWithValue(_PostRepository()),
          threadRepositoryProvider.overrideWithValue(_ThreadRepository()),
        ],
        child: MaterialApp(
          home: InboxThreadHost(
            showAdjacentWorkspace: true,
            background: const Text('Current workspace'),
            inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
              child: FilledButton(
                onPressed: () => onOpenItem(item),
                child: const Text('Inbox DM bundle'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Inbox DM bundle'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('1 reply'));
    await tester.pumpAndSettle();

    expect(find.text('Inbox DM bundle'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('message-input-direct-channel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('thread-direct-channel-root')),
      findsOneWidget,
    );
    expect(find.text('DM thread reply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact DM and thread Back stack returns to Inbox', (
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
          _post(id: 'direct-message-1', channelId: directChannel.id),
          directChannel,
        ),
        _candidate(
          _post(id: 'direct-message-2', channelId: directChannel.id),
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
            showAdjacentWorkspace: false,
            background: const Text('Current workspace'),
            inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
              child: FilledButton(
                onPressed: () => onOpenItem(item),
                child: const Text('Inbox DM bundle'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: InboxChannelRoute.path,
          builder: (BuildContext context, GoRouterState state) =>
              InboxChannelRoute.build(
                context,
                state.extra! as InboxChannelRouteArguments,
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
          authSessionProvider.overrideWithValue(_session),
          postRepositoryProvider.overrideWithValue(_PostRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('Inbox DM bundle'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox DM bundle'), findsNothing);
    expect(find.text('DM chat message'), findsOneWidget);

    await tester.tap(find.textContaining('1 reply'));
    await tester.pumpAndSettle();
    expect(find.text('Route thread direct-channel-root'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('DM chat message'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Inbox DM bundle'), findsOneWidget);
    expect(find.text('DM chat message'), findsNothing);
  });

  testWidgets('opens a single direct message as a thread', (
    WidgetTester tester,
  ) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_NoopAuthRepository()),
        ],
        child: MaterialApp(
          home: InboxThreadHost(
            showAdjacentWorkspace: true,
            background: const Text('Current workspace'),
            inboxBuilder: (_, ValueChanged<InboxItem> onOpenItem) => Center(
              child: FilledButton(
                onPressed: () => onOpenItem(item),
                child: const Text('Direct message'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Direct message'));
    await tester.pump();

    expect(find.byType(ChannelPostsPane), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('inbox-thread-direct-message')),
      findsOneWidget,
    );
  });
}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.com'),
  userId: 'me',
  username: 'current',
);

final class _PostRepository extends PostRepository {
  _PostRepository({this.navigationTarget});

  final PostNavigationTarget? navigationTarget;

  @override
  Future<PostNavigationTarget> resolveNavigationTarget({
    required AuthSession session,
    required String postId,
  }) {
    final PostNavigationTarget? target = navigationTarget;
    if (target == null) {
      return Future<PostNavigationTarget>.error(
        StateError('No navigation target for $postId'),
      );
    }
    return Future<PostNavigationTarget>.value(target);
  }

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => ChannelPostPage(
    posts: <ChannelPost>[
      ChannelPost(
        id: '$channelId-root',
        channelId: channelId,
        author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
        sentAt: DateTime.utc(2026, 9, 4, 12),
        message: 'DM chat message',
        replyCount: 1,
      ),
    ],
    hasOlder: false,
  );

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();

  @override
  Future<ChannelPostPage> loadAround({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async => ChannelPostPage(
    posts: <ChannelPost>[
      ChannelPost(
        id: postId,
        channelId: channelId,
        author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
        sentAt: DateTime.utc(2026, 9, 4, 12),
        message: 'Focused message',
      ),
    ],
    hasOlder: false,
  );
}

final class _ThreadRepository extends ThreadRepository {
  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async => MessageThread(
    rootPostId: rootPostId,
    root: ChannelPost(
      id: rootPostId,
      channelId: 'direct-channel',
      author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
      sentAt: DateTime.utc(2026, 9, 4, 12),
      message: 'DM chat message',
      replyCount: 1,
    ),
    replies: <ChannelPost>[
      ChannelPost(
        id: 'direct-reply',
        channelId: 'direct-channel',
        author: const PostAuthor(id: 'me', displayName: 'Current User'),
        sentAt: DateTime.utc(2026, 9, 4, 12, 1),
        message: 'DM thread reply',
        rootId: rootPostId,
      ),
    ],
    isComplete: true,
    loadedAt: DateTime.utc(2026, 9, 4, 12, 2),
  );
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
