import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar.dart';
import 'package:mattermost_flutter/src/features/channels/domain/channel_sidebar_repository.dart';
import 'package:mattermost_flutter/src/features/channels/presentation/channel_sidebar_controller.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post.dart';
import 'package:mattermost_flutter/src/features/posts/domain/channel_post_repository.dart';
import 'package:mattermost_flutter/src/features/posts/presentation/channel_posts_controller.dart';
import 'package:mattermost_flutter/src/features/threads/domain/message_thread.dart';
import 'package:mattermost_flutter/src/features/threads/domain/thread_repository.dart';
import 'package:mattermost_flutter/src/features/threads/presentation/thread_controller.dart';

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
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
          ),
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

  testWidgets('loads mock messages after selecting a channel', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
          ),
          channelPostRepositoryProvider.overrideWithValue(
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
    expect(find.text('👍  3'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
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
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
          ),
          channelPostRepositoryProvider.overrideWithValue(
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
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
          ),
          channelPostRepositoryProvider.overrideWithValue(
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

  testWidgets('opens a thread over the channel on compact width', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
          ),
          channelPostRepositoryProvider.overrideWithValue(
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

  testWidgets('keeps refreshed posts hidden until Show recent messages', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _RecentPostRepository posts = _RecentPostRepository();
    addTearDown(posts.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
          ),
          channelPostRepositoryProvider.overrideWithValue(posts),
        ],
        child: const MaterialApp(home: BootstrapPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Town Square'));
    await tester.pumpAndSettle();

    expect(find.text('Cached message'), findsOneWidget);
    expect(find.text('New message'), findsNothing);
    expect(find.text('Show recent messages'), findsOneWidget);

    await tester.tap(find.text('Show recent messages'));
    await tester.pumpAndSettle();
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Show recent messages'), findsNothing);
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
          channelSidebarRepositoryProvider.overrideWithValue(
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

  testWidgets('applies collapsed and muted category presentation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedInRepository()),
          channelSidebarRepositoryProvider.overrideWithValue(
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
          channelSidebarRepositoryProvider.overrideWithValue(
            _SidebarRepository(),
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

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _SignedOutRepository implements AuthRepository {
  @override
  Future<AuthSession> authenticateWithPersonalAccessToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  Future<void> signOut() async {}
}

final class _DelayedPostRepository implements ChannelPostRepository {
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
  Future<void> loadOlder({
    required AuthSession session,
    required String channelId,
  }) async {}

  @override
  Future<ChannelPostSnapshot> read({
    required String accountId,
    required String channelId,
  }) async =>
      ChannelPostSnapshot(posts: await _posts(channelId), hasOlder: false);

  @override
  Future<ChannelPostRefreshResult> refreshLatest({
    required AuthSession session,
    required String channelId,
  }) async => const ChannelPostRefreshResult(newPostIds: <String>{});

  @override
  Stream<ChannelPostSnapshot> watch({
    required String accountId,
    required String channelId,
  }) => const Stream<ChannelPostSnapshot>.empty();
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
        message: 'Thread reply 2',
        rootId: rootPostId,
      ),
    ],
    isComplete: true,
  );

  @override
  Future<MessageThread> read({
    required String accountId,
    required String rootPostId,
  }) async => _thread(rootPostId);

  @override
  Future<void> refresh({
    required AuthSession session,
    required String rootPostId,
  }) async {}

  @override
  Stream<MessageThread> watch({
    required String accountId,
    required String rootPostId,
  }) async* {
    yield _thread(rootPostId);
  }
}

final class _RecentPostRepository implements ChannelPostRepository {
  final StreamController<ChannelPostSnapshot> _changes =
      StreamController<ChannelPostSnapshot>.broadcast();

  ChannelPostSnapshot get _cached => ChannelPostSnapshot(
    posts: <ChannelPost>[
      ChannelPost(
        id: 'cached',
        channelId: 'town-square',
        author: const PostAuthor(id: 'ada', displayName: 'Ada'),
        sentAt: DateTime(2026, 8, 24, 10),
        message: 'Cached message',
      ),
    ],
    hasOlder: false,
  );

  ChannelPostSnapshot get _refreshed => ChannelPostSnapshot(
    posts: <ChannelPost>[
      ..._cached.posts,
      ChannelPost(
        id: 'new',
        channelId: 'town-square',
        author: const PostAuthor(id: 'ada', displayName: 'Ada'),
        sentAt: DateTime(2026, 8, 24, 11),
        message: 'New message',
      ),
    ],
    hasOlder: false,
  );

  Future<void> close() => _changes.close();

  @override
  Future<void> loadOlder({
    required AuthSession session,
    required String channelId,
  }) async {}

  @override
  Future<ChannelPostSnapshot> read({
    required String accountId,
    required String channelId,
  }) async => _cached;

  @override
  Future<ChannelPostRefreshResult> refreshLatest({
    required AuthSession session,
    required String channelId,
  }) async {
    _changes.add(_refreshed);
    return const ChannelPostRefreshResult(newPostIds: <String>{'new'});
  }

  @override
  Stream<ChannelPostSnapshot> watch({
    required String accountId,
    required String channelId,
  }) => _changes.stream;
}

final class _SignedInRepository implements AuthRepository {
  @override
  Future<AuthSession> authenticateWithPersonalAccessToken({
    required Uri serverUrl,
    required String token,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession?> restoreSession() async => AuthSession(
    serverUrl: Uri.parse('https://chat.example.com'),
    userId: 'me',
    username: 'current',
  );

  @override
  Future<void> signOut() async {}
}

final class _SidebarRepository implements ChannelSidebarRepository {
  @override
  Future<void> refresh(AuthSession session) async {}

  @override
  Stream<ChannelSidebarSnapshot> watch(String accountId) =>
      Stream<ChannelSidebarSnapshot>.value(
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
        ),
      );
}

final class _LargeSidebarRepository implements ChannelSidebarRepository {
  @override
  Future<void> refresh(AuthSession session) async {}

  @override
  Stream<ChannelSidebarSnapshot> watch(String accountId) =>
      Stream<ChannelSidebarSnapshot>.value(
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
        ),
      );
}

final class _CollapsedMutedSidebarRepository
    implements ChannelSidebarRepository {
  @override
  Future<void> refresh(AuthSession session) async {}

  @override
  Stream<ChannelSidebarSnapshot> watch(String accountId) =>
      Stream<ChannelSidebarSnapshot>.value(
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
        ),
      );
}
