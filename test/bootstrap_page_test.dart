import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/channel_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/followed_threads_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/ui/shell/shell_page.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('uses a drawer on compact screens', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedOutRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.drawer, isA<Drawer>());
    expect(find.text('Mattermost'), findsOneWidget);
  });

  testWidgets('shows categorized channels and dialogs when signed in', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Example team'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Town Square'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('shows the unread reply count for followed threads', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          followedThreadsRepositoryProvider.overrideWithValue(
            const _FollowedThreadsRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Mentioned root'), findsOneWidget);
    expect(find.text('Unread root'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('thread-unread-count-root-mention')),
      findsOneWidget,
    );
    expect(find.text('3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('thread-unread-count-root-unread')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('positions a followed thread at unread replies then marks read', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _ReadRecordingThreadRepository threads =
        _ReadRecordingThreadRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          followedThreadsRepositoryProvider.overrideWithValue(
            const _FollowedThreadsRepository(),
          ),
          threadRepositoryProvider.overrideWithValue(threads),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unread root'));
    await tester.pumpAndSettle();

    expect(find.text('unread messages'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('unread messages')).dy,
      lessThan(tester.getTopLeft(find.text('This message was deleted')).dy),
    );
    expect(threads.markReadCalls, 1);
    expect(threads.teamId, 'team-1');
    expect(threads.rootPostId, 'root-unread');
    expect(threads.timestamp, DateTime.fromMillisecondsSinceEpoch(123456));
    expect(
      find.byKey(const ValueKey<String>('thread-unread-count-root-unread')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows threads on compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          followedThreadsRepositoryProvider.overrideWithValue(
            const _FollowedThreadsRepository(),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BootstrapPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Mentioned root'), findsOneWidget);
    expect(find.text('Unread root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads mock messages after selecting a channel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Town Square'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Message for town-square'), findsNothing);

    await tester.pump(const Duration(milliseconds: 799));
    expect(find.text('Message for town-square'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Message for town-square'), findsOneWidget);
    expect(find.text('Follow-up message 1'), findsOneWidget);
    expect(find.text('Follow-up message 2'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reaction-👍')), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('sends a text message in the selected channel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecordingPostRepository sender = _RecordingPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(sender),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('message-input-town-square')),
      'New channel message',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('send-message-town-square')),
    );
    await tester.pumpAndSettle();

    expect(sender.channelId, 'town-square');
    expect(sender.rootPostId, isEmpty);
    expect(sender.message, 'New channel message');
    expect(sender.pendingPostId, isNotEmpty);
    expect(find.text('New channel message'), findsOneWidget);
  });

  testWidgets('sends a text reply and updates both thread and root summary', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecordingPostRepository sender = _RecordingPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(sender),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        const ValueKey<String>('message-input-thread-town-square-post'),
      ),
      'New thread reply',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('send-message-thread-town-square-post'),
      ),
    );
    await tester.pumpAndSettle();

    expect(sender.channelId, 'town-square');
    expect(sender.rootPostId, 'town-square-post');
    expect(sender.message, 'New thread reply');
    expect(find.text('New thread reply'), findsOneWidget);
    expect(find.textContaining('3 replies'), findsWidgets);

    await tester.tap(find.byTooltip('Close thread'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 replies'), findsOneWidget);
  });

  testWidgets('shows messages on compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BootstrapPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(find.text('Message for town-square'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a thread beside the channel on expanded width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    expect(find.text('Thread'), findsOneWidget);
    expect(find.text('Thread reply 1'), findsOneWidget);
    expect(find.text('This message was deleted'), findsOneWidget);
    expect(find.text('Deleted reply contents'), findsNothing);
    expect(find.text('Message for town-square'), findsNWidgets(2));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      380,
    );
  });

  testWidgets('opens a channel thread without changing its initial position', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    final ListView messages = tester.widget<ListView>(
      find.byKey(
        const ValueKey<String>('thread-message-list-town-square-post'),
      ),
    );
    expect(messages.controller?.position.pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a thread over the channel on compact width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(
            const _DelayedPostRepository(delay: Duration.zero),
          ),
          threadRepositoryProvider.overrideWithValue(const _ThreadRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 replies'));
    await tester.pumpAndSettle();

    expect(find.text('Thread'), findsOneWidget);
    expect(find.text('Thread reply 1'), findsOneWidget);
    expect(find.text('Message for town-square'), findsNWidgets(2));
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('thread-town-square-post')),
          )
          .width,
      390,
    );
  });

  testWidgets('auto-pages when replies leave a short root list unscrollable', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 2);
    expect(find.text('Older root'), findsOneWidget);
  });

  testWidgets('auto-pages when a page contains no visible roots', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository(
      startsEmpty: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 2);
    expect(find.text('Older root'), findsOneWidget);
    expect(find.textContaining('1 reply'), findsOneWidget);
  });

  testWidgets('stops viewport auto-paging after a paging failure', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository(
      failLoads: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 1);
  });

  testWidgets('bounds viewport auto-paging and leaves a manual fallback', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _AutoPagingPostRepository posts = _AutoPagingPostRepository(
      neverCompletes: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
          postRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(posts.loadOlderCalls, 20);
    expect(find.text('Load older messages'), findsOneWidget);
  });

  testWidgets('lazily builds channels in a large expandable category', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _LargeSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Channel 0'), findsOneWidget);
    expect(find.text('Channel 199'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));

    await tester.tap(find.text('Large category'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsNothing);

    await tester.tap(find.text('Large category'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
  });

  testWidgets('uses compact vertical spacing for channel rows', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder channelTile = find.ancestor(
      of: find.text('Town Square'),
      matching: find.byType(ListTile),
    );
    expect(
      tester.widget<ListTile>(channelTile).visualDensity,
      const VisualDensity(vertical: -2),
    );
  });

  testWidgets('applies collapsed and muted category presentation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(
            _CollapsedMutedSidebarRepository(),
          ),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Muted category'), findsOneWidget);
    expect(find.text('Quiet channel'), findsNothing);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Muted category'),
              matching: find.byType(Opacity),
            ),
          )
          .any((Opacity opacity) => opacity.opacity == 0.55),
      isTrue,
    );

    await tester.tap(find.text('Muted category'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet channel'), findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Quiet channel'),
              matching: find.byType(Opacity),
            ),
          )
          .any((Opacity opacity) => opacity.opacity == 0.55),
      isTrue,
    );
  });

  testWidgets('shows the channel list in compact drawer at large text scale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelRepositoryProvider.overrideWithValue(_SidebarRepository()),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: BootstrapPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _SignedOutRepository implements AuthRepository {
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

class _DelayedPostRepository extends PostRepository {
  const _DelayedPostRepository({
    this.delay = const Duration(milliseconds: 800),
  });

  final Duration delay;

  Future<List<ChannelPost>> _posts(String channelId) async {
    await Future<void>.delayed(delay);
    return <ChannelPost>[
      ChannelPost(
        id: '$channelId-post',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 30),
        message: 'Message for $channelId',
        reactions: const <PostReaction>[PostReaction(emoji: '👍', count: 3)],
        replyCount: 2,
        lastReplyAt: DateTime(2026, 8, 24, 10, 35),
      ),
      ChannelPost(
        id: '$channelId-follow-up-1',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 31),
        message: 'Follow-up message 1',
      ),
      ChannelPost(
        id: '$channelId-follow-up-2',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 32),
        message: 'Follow-up message 2',
      ),
    ];
  }

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => ChannelPostPage(posts: await _posts(channelId), hasOlder: false);
}

final class _ThreadRepository implements ThreadRepository {
  const _ThreadRepository();

  MessageThread _thread(String rootPostId) => MessageThread(
    rootPostId: rootPostId,
    root: ChannelPost(
      id: rootPostId,
      channelId: 'town-square',
      author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
      sentAt: DateTime(2026, 8, 24, 10, 30),
      message: 'Message for town-square',
      replyCount: 2,
    ),
    replies: <ChannelPost>[
      ChannelPost(
        id: 'reply-1',
        channelId: 'town-square',
        author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
        sentAt: DateTime(2026, 8, 24, 10, 31),
        message: 'Thread reply 1',
        rootId: rootPostId,
      ),
      ChannelPost(
        id: 'reply-2',
        channelId: 'town-square',
        author: const PostAuthor(id: 'alan', displayName: 'Alan Turing'),
        sentAt: DateTime(2026, 8, 24, 10, 35),
        message: 'Deleted reply contents',
        rootId: rootPostId,
        isDeleted: true,
      ),
    ],
    isComplete: true,
    loadedAt: DateTime.fromMillisecondsSinceEpoch(123456),
  );

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async => _thread(rootPostId);

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) async {}
}

final class _ReadRecordingThreadRepository implements ThreadRepository {
  int markReadCalls = 0;
  String? teamId;
  String? rootPostId;
  DateTime? timestamp;

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) =>
      const _ThreadRepository().load(session: session, rootPostId: rootPostId);

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) async {
    markReadCalls += 1;
    this.teamId = teamId;
    this.rootPostId = rootPostId;
    this.timestamp = timestamp;
  }
}

final class _RecordingPostRepository extends _DelayedPostRepository {
  _RecordingPostRepository() : super(delay: Duration.zero);

  String? channelId;
  String? rootPostId;
  String? message;
  String? pendingPostId;
  var _nextId = 0;

  @override
  Future<ChannelPost> sendText({
    required AuthSession session,
    required String channelId,
    required String message,
    required String pendingPostId,
    String rootPostId = '',
  }) async {
    this.channelId = channelId;
    this.rootPostId = rootPostId;
    this.message = message;
    this.pendingPostId = pendingPostId;
    _nextId += 1;
    return ChannelPost(
      id: 'sent-$_nextId',
      channelId: channelId,
      author: PostAuthor(id: session.userId, displayName: session.username),
      sentAt: DateTime(2026, 8, 25, 12, _nextId),
      message: message,
      rootId: rootPostId,
    );
  }
}

final class _AutoPagingPostRepository extends PostRepository {
  _AutoPagingPostRepository({
    this.startsEmpty = false,
    this.failLoads = false,
    this.neverCompletes = false,
  });

  final bool startsEmpty;
  final bool failLoads;
  final bool neverCompletes;
  int loadOlderCalls = 0;

  ChannelPost get _recent => ChannelPost(
    id: 'recent-root',
    channelId: 'town-square',
    author: const PostAuthor(id: 'ada', displayName: 'Ada'),
    sentAt: DateTime(2026, 8, 24, 12),
    message: 'Recent root',
    replyCount: 60,
  );

  ChannelPostPage get _initial => ChannelPostPage(
    posts: startsEmpty ? const <ChannelPost>[] : <ChannelPost>[_recent],
    replySummaries: startsEmpty
        ? <String, ChannelReplySummary>{
            'older-root': ChannelReplySummary(
              replyIds: const <String>{'reply-1'},
              lastReplyAt: DateTime(2026, 8, 24, 11, 30),
            ),
          }
        : const <String, ChannelReplySummary>{},
    beforePostId: 'cursor-0',
    hasOlder: true,
  );

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async {
    loadOlderCalls += 1;
    if (failLoads) throw StateError('paging failed');
    if (neverCompletes) {
      return ChannelPostPage(
        beforePostId: 'cursor-$loadOlderCalls',
        hasOlder: true,
      );
    }
    if (loadOlderCalls == 1) {
      return ChannelPostPage(
        replySummaries: startsEmpty
            ? const <String, ChannelReplySummary>{
                'older-root': ChannelReplySummary(
                  replyIds: <String>{'reply-1'},
                ),
              }
            : const <String, ChannelReplySummary>{},
        beforePostId: 'cursor-1',
        hasOlder: true,
      );
    }
    return ChannelPostPage(
      posts: <ChannelPost>[
        ChannelPost(
          id: 'older-root',
          channelId: channelId,
          author: const PostAuthor(id: 'grace', displayName: 'Grace'),
          sentAt: DateTime(2026, 8, 24, 11),
          message: 'Older root',
        ),
      ],
      hasOlder: false,
    );
  }

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => _initial;
}

final class _SignedInRepository implements AuthRepository {
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
  Future<AuthSession?> restoreSession() async => AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'current',
  );

  @override
  Future<void> signOut() async {}
}

final class _SidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      const ChannelSidebarSnapshot(
        team: SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'favorites',
            displayName: 'Favorites',
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'town-square',
                teamId: 'team-1',
                name: 'town-square',
                displayName: 'Town Square',
                kind: ChannelKind.publicChannel,
              ),
              SidebarChannel(
                id: 'direct-1',
                teamId: '',
                name: 'me__ada',
                displayName: 'Ada Lovelace',
                kind: ChannelKind.directMessage,
              ),
            ],
          ),
        ],
      );
}

final class _FollowedThreadsRepository implements FollowedThreadsRepository {
  const _FollowedThreadsRepository();

  @override
  Future<FollowedThreadsPage> loadPage({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async => FollowedThreadsPage(
    total: 2,
    totalUnreadThreads: 2,
    totalUnreadMentions: 2,
    items: <FollowedThread>[
      FollowedThread(
        root: ChannelPost(
          id: 'root-mention',
          channelId: 'town-square',
          author: const PostAuthor(id: 'ada', displayName: 'Ada Lovelace'),
          sentAt: DateTime(2026, 8, 24, 10),
          message: 'Mentioned root',
        ),
        replyCount: 4,
        lastReplyAt: DateTime(2026, 8, 25, 10),
        lastViewedAt: DateTime(2026, 8, 24, 10),
        unreadReplies: 3,
        unreadMentions: 2,
      ),
      FollowedThread(
        root: ChannelPost(
          id: 'root-unread',
          channelId: 'town-square',
          author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
          sentAt: DateTime(2026, 8, 24, 11),
          message: 'Unread root',
        ),
        replyCount: 2,
        lastReplyAt: DateTime(2026, 8, 25, 11),
        lastViewedAt: DateTime(2026, 8, 24, 11),
        unreadReplies: 1,
        unreadMentions: 0,
      ),
    ],
  );
}

final class _LargeSidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      ChannelSidebarSnapshot(
        team: const SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'large',
            displayName: 'Large category',
            channels: List<SidebarChannel>.generate(
              200,
              (int index) => SidebarChannel(
                id: 'channel-$index',
                teamId: 'team-1',
                name: 'channel-$index',
                displayName: 'Channel $index',
                kind: ChannelKind.publicChannel,
              ),
              growable: false,
            ),
          ),
        ],
      );
}

final class _CollapsedMutedSidebarRepository implements ChannelRepository {
  @override
  Future<SidebarChannel> openDirectMessage({
    required String currentUserId,
    required String otherUserId,
    required String otherUserDisplayName,
  }) async => throw UnimplementedError();

  @override
  Future<ChannelSidebarSnapshot> load(AuthSession session) async =>
      const ChannelSidebarSnapshot(
        team: SidebarTeam(id: 'team-1', displayName: 'Example team'),
        sections: <SidebarSection>[
          SidebarSection(
            id: 'muted',
            displayName: 'Muted category',
            collapsed: true,
            muted: true,
            channels: <SidebarChannel>[
              SidebarChannel(
                id: 'quiet',
                teamId: 'team-1',
                name: 'quiet',
                displayName: 'Quiet channel',
                kind: ChannelKind.publicChannel,
              ),
            ],
          ),
        ],
      );
}
