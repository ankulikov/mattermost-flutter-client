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
}

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
