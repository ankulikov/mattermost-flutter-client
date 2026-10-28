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
  for (final (double width, ThemeMode mode, double scale)
      in <(double, ThemeMode, double)>[
        (320, ThemeMode.light, 1),
        (799, ThemeMode.dark, 1),
        (800, ThemeMode.light, 2),
        (1200, ThemeMode.dark, 2),
      ]) {
    testWidgets('thread row at width $width, $mode, text scale $scale', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWithValue(
              AuthSession(
                serverUrl: Uri.parse('https://example.com'),
                userId: 'me',
                username: 'me',
              ),
            ),
            threadRepositoryProvider.overrideWithValue(_ThreadsRepository()),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: mode,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: FollowedThreadsPane(
                  team: SidebarTeam(id: 'team', displayName: 'Team'),
                  channelsById: <String, SidebarChannel>{
                    'channel': SidebarChannel(
                      id: 'channel',
                      teamId: 'team',
                      name: 'town-square',
                      displayName: 'Town Square',
                      kind: ChannelKind.publicChannel,
                    ),
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Root preview'), findsOneWidget);
      expect(find.text('Town Square'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('thread-unread-count-root')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final SemanticsHandle semantics = tester.ensureSemantics();
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics &&
              widget.properties.label == 'Ada, Town Square, 2 unread replies',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  }
}

final class _ThreadsRepository extends ThreadRepository {
  @override
  Future<FollowedThreadsPage> loadFollowed({
    required AuthSession session,
    required String teamId,
    String? before,
    int perPage = 60,
  }) async => FollowedThreadsPage(
    items: <FollowedThread>[
      FollowedThread(
        root: Post(
          id: 'root',
          channelId: 'channel',
          author: const PostAuthor(id: 'ada', displayName: 'Ada'),
          sentAt: DateTime.utc(2026, 10, 1),
          message: 'Root preview',
        ),
        replyCount: 3,
        lastReplyAt: DateTime.utc(2026, 10, 2),
        lastViewedAt: DateTime.utc(2026, 10, 1),
        unreadReplies: 2,
        unreadMentions: 0,
      ),
    ],
    total: 1,
    totalUnreadThreads: 1,
    totalUnreadMentions: 0,
  );
}
