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

  @override
  Future<List<ChannelPost>> loadHistory(String channelId) async {
    await Future<void>.delayed(delay);
    return <ChannelPost>[
      ChannelPost(
        id: '$channelId-post',
        channelId: channelId,
        author: const PostAuthor(id: 'grace', displayName: 'Grace Hopper'),
        sentAt: DateTime(2026, 8, 24, 10, 30),
        message: 'Message for $channelId',
        reactions: const <PostReaction>[PostReaction(emoji: '👍', count: 3)],
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
