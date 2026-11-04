import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/followed_threads_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('shows the latest reply time in the card header', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now();
    final FollowedThread thread = FollowedThread(
      root: ChannelPost(
        id: 'thread-1',
        channelId: 'channel-1',
        author: PostAuthor(id: 'root-author', displayName: 'Root author'),
        sentAt: DateTime(2026, 1, 1),
        message: 'Root message',
      ),
      replyCount: 2,
      lastReplyAt: now.subtract(const Duration(minutes: 5)),
      lastViewedAt: now.subtract(const Duration(days: 1)),
      unreadReplies: 0,
      unreadMentions: 0,
    );
    await _pumpThread(tester, thread: thread);

    final Finder header = find.text('channel-1');
    final Finder time = find.byKey(
      const ValueKey<String>('followed-thread-last-reply-time-thread-1'),
    );
    expect(time, findsOneWidget);
    expect(find.text('5 minutes ago'), findsOneWidget);
    expect(
      tester.getTopLeft(time).dx,
      greaterThan(tester.getTopLeft(header).dx),
    );
    expect(
      (tester.getTopLeft(time).dy - tester.getTopLeft(header).dy).abs(),
      lessThanOrEqualTo(4),
    );
  });

  for (final (double width, double scale) in <(double, double)>[
    (360, 1),
    (1000, 1.5),
  ]) {
    testWidgets(
      'shows unread replies and mentions at width $width scale $scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final FollowedThread thread = FollowedThread(
          root: ChannelPost(
            id: 'thread-1',
            channelId: 'channel-1',
            author: PostAuthor(id: 'root-author', displayName: 'Root author'),
            sentAt: DateTime(2026),
            message: 'Root message',
          ),
          replyCount: 18,
          lastReplyAt: DateTime(2026),
          lastViewedAt: DateTime(2026),
          unreadReplies: 2,
          unreadMentions: 1,
          participants: <PostAuthor>[
            PostAuthor(id: 'participant-1', displayName: 'Participant one'),
          ],
        );
        await _pumpThread(tester, thread: thread, scale: scale, width: width);
        expect(find.text('Threads'), findsOneWidget);
        expect(find.text('2 new replies'), findsOneWidget);
        expect(find.text('18 replies'), findsNothing);
        final Finder dot = find.byKey(
          const ValueKey<String>('thread-unread-dot-thread-1'),
        );
        final Finder avatar = find.byKey(
          const ValueKey<String>('user-avatar-fallback-participant-1'),
        );
        expect(dot, findsNothing);
        final Finder badge = find.byKey(
          const ValueKey<String>('thread-unread-count-thread-1'),
        );
        expect(
          find.descendant(of: badge, matching: find.text('1')),
          findsOneWidget,
        );
        final Finder rootAvatar = find.byKey(
          const ValueKey<String>('user-avatar-fallback-root-author'),
        );
        expect(tester.getCenter(badge).dx, tester.getCenter(rootAvatar).dx);
        expect(tester.getSize(badge).width, tester.getSize(badge).height);
        expect(
          tester.getTopLeft(badge).dx,
          lessThan(tester.getTopLeft(avatar).dx),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('read thread shows total replies without unread indicators', (
    WidgetTester tester,
  ) async {
    await _pumpThreads(tester, participantCount: 1);
    expect(find.text('2 replies'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('thread-unread-dot-thread-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('thread-unread-count-thread-1')),
      findsNothing,
    );
  });

  testWidgets('unread replies without mentions do not show a count badge', (
    WidgetTester tester,
  ) async {
    final thread = FollowedThread(
      root: ChannelPost(
        id: 'thread-1',
        channelId: 'channel-1',
        author: PostAuthor(id: 'root-author', displayName: 'Root author'),
        sentAt: DateTime(2026),
        message: 'Root message',
      ),
      replyCount: 2,
      lastReplyAt: DateTime(2026),
      lastViewedAt: DateTime(2026),
      unreadReplies: 1,
      unreadMentions: 0,
    );
    await _pumpThread(tester, thread: thread);
    expect(find.text('1 new reply'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('thread-unread-dot-thread-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('thread-unread-count-thread-1')),
      findsNothing,
    );
    expect(
      tester
          .getCenter(
            find.byKey(const ValueKey<String>('thread-unread-dot-thread-1')),
          )
          .dx,
      tester
          .getCenter(
            find.byKey(
              const ValueKey<String>('user-avatar-fallback-root-author'),
            ),
          )
          .dx,
    );
  });

  testWidgets('formats latest-reply times across age ranges', (
    WidgetTester tester,
  ) async {
    await _pumpThreads(tester, participantCount: 0);
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      tester.element(find.byType(FollowedThreadsPane)),
    );
    final DateTime now = DateTime(2026, 10, 30, 12);

    expect(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: now.subtract(const Duration(seconds: 30)),
        now: now,
        localizations: localizations,
      ),
      'now',
    );
    expect(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: now.subtract(const Duration(minutes: 1)),
        now: now,
        localizations: localizations,
      ),
      '1 minute ago',
    );
    expect(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: now.subtract(const Duration(minutes: 59)),
        now: now,
        localizations: localizations,
      ),
      '59 minutes ago',
    );
    expect(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: now.subtract(const Duration(hours: 1)),
        now: now,
        localizations: localizations,
      ),
      '1 hour ago',
    );
    expect(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: now.subtract(const Duration(hours: 23)),
        now: now,
        localizations: localizations,
      ),
      '23 hours ago',
    );

    final DateTime olderReply = now.subtract(const Duration(days: 2));
    expect(
      formatFollowedThreadLastReplyTime(
        lastReplyAt: olderReply,
        now: now,
        localizations: localizations,
      ),
      localizations.formatMediumDate(olderReply),
    );
  });

  testWidgets('aligns and slightly overlaps thread participant avatars', (
    WidgetTester tester,
  ) async {
    final FollowedThread thread = FollowedThread(
      root: ChannelPost(
        id: 'thread-1',
        channelId: 'channel-1',
        author: PostAuthor(id: 'root-author', displayName: 'Root author'),
        sentAt: DateTime(2026, 10, 31),
        message: 'Root message',
      ),
      replyCount: 2,
      lastReplyAt: DateTime(2026, 10, 31),
      lastViewedAt: DateTime(2026, 10, 30),
      unreadReplies: 0,
      unreadMentions: 0,
      participants: <PostAuthor>[
        PostAuthor(id: 'participant-1', displayName: 'Participant one'),
        PostAuthor(id: 'participant-2', displayName: 'Participant two'),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(
            AuthSession(
              serverUrl: Uri.parse('https://chat.example.com'),
              userId: 'me',
              username: 'ada',
            ),
          ),
          threadRepositoryProvider.overrideWithValue(_ThreadRepository(thread)),
          userAvatarProvider.overrideWith(
            (Ref ref, UserAvatarRequest request) async => null,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: FollowedThreadsPane(
                team: SidebarTeam(id: 'team-1', displayName: 'Team'),
                channelsById: <String, SidebarChannel>{},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder message = find.text('Root message');
    final Finder firstAvatar = find.byKey(
      const ValueKey<String>('user-avatar-fallback-participant-1'),
    );
    final Finder secondAvatar = find.byKey(
      const ValueKey<String>('user-avatar-fallback-participant-2'),
    );
    expect(message, findsOneWidget);
    expect(firstAvatar, findsOneWidget);
    expect(secondAvatar, findsOneWidget);

    expect(tester.getTopLeft(firstAvatar).dx, tester.getTopLeft(message).dx);
    expect(
      tester.getTopLeft(secondAvatar).dx,
      lessThan(tester.getBottomRight(firstAvatar).dx),
    );
  });

  testWidgets('shows all four participant avatars without an overflow count', (
    WidgetTester tester,
  ) async {
    await _pumpThreads(tester, participantCount: 4);

    for (int index = 1; index <= 4; index += 1) {
      expect(
        find.byKey(ValueKey<String>('user-avatar-fallback-participant-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(
        const ValueKey<String>('thread-additional-participants-thread-1'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'shows three avatars and names the remaining participants on hover',
    (WidgetTester tester) async {
      await _pumpThreads(tester, participantCount: 5);

      for (int index = 1; index <= 3; index += 1) {
        expect(
          find.byKey(
            ValueKey<String>('user-avatar-fallback-participant-$index'),
          ),
          findsOneWidget,
        );
      }
      for (int index = 4; index <= 5; index += 1) {
        expect(
          find.byKey(
            ValueKey<String>('user-avatar-fallback-participant-$index'),
          ),
          findsNothing,
        );
      }

      final Finder overflow = find.byKey(
        const ValueKey<String>('thread-additional-participants-thread-1'),
      );
      expect(overflow, findsOneWidget);
      expect(find.text('+2'), findsOneWidget);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: tester.getCenter(overflow));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Participant four, Participant five'), findsOneWidget);
    },
  );
}

Future<void> _pumpThreads(
  WidgetTester tester, {
  required int participantCount,
}) async {
  final List<PostAuthor> participants = List<PostAuthor>.generate(
    participantCount,
    (int index) => PostAuthor(
      id: 'participant-${index + 1}',
      displayName: 'Participant ${_numberName(index + 1)}',
    ),
  );
  final FollowedThread thread = FollowedThread(
    root: ChannelPost(
      id: 'thread-1',
      channelId: 'channel-1',
      author: PostAuthor(id: 'root-author', displayName: 'Root author'),
      sentAt: DateTime(2026, 10, 31),
      message: 'Root message',
    ),
    replyCount: 2,
    lastReplyAt: DateTime(2026, 10, 31),
    lastViewedAt: DateTime(2026, 10, 30),
    unreadReplies: 0,
    unreadMentions: 0,
    participants: participants,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWithValue(
          AuthSession(
            serverUrl: Uri.parse('https://chat.example.com'),
            userId: 'me',
            username: 'ada',
          ),
        ),
        threadRepositoryProvider.overrideWithValue(_ThreadRepository(thread)),
        userAvatarProvider.overrideWith(
          (Ref ref, UserAvatarRequest request) async => null,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: FollowedThreadsPane(
              team: SidebarTeam(id: 'team-1', displayName: 'Team'),
              channelsById: <String, SidebarChannel>{},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpThread(
  WidgetTester tester, {
  required FollowedThread thread,
  double scale = 1,
  double width = 500,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWithValue(
          AuthSession(
            serverUrl: Uri.parse('https://chat.example.com'),
            userId: 'me',
            username: 'ada',
          ),
        ),
        threadRepositoryProvider.overrideWithValue(_ThreadRepository(thread)),
        userAvatarProvider.overrideWith(
          (Ref ref, UserAvatarRequest request) async => null,
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: const FollowedThreadsPane(
              team: SidebarTeam(id: 'team-1', displayName: 'Team'),
              channelsById: <String, SidebarChannel>{},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _numberName(int number) =>
    <String>['one', 'two', 'three', 'four', 'five'][number - 1];

final class _ThreadRepository extends ThreadRepository {
  const _ThreadRepository(this.thread);

  final FollowedThread thread;

  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
  }) async => FollowedThreadsPage(
    items: <FollowedThread>[thread],
    total: 1,
    totalUnreadThreads: 0,
    totalUnreadMentions: 0,
    hasMore: false,
  );
}
