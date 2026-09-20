import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/post_navigation.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_action_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/channel_posts_pane.dart';
import 'package:mattermost_flutter/src/ui/posts/widgets/linked_post_page.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets(
    'shared interactive card renders in channel, thread, and permalink hosts',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final _Posts posts = _Posts();
      final _Actions actions = _Actions();
      addTearDown(actions.dispose);
      final overrides = [
        authSessionProvider.overrideWithValue(_session),
        postRepositoryProvider.overrideWithValue(posts),
        threadRepositoryProvider.overrideWithValue(const _Threads()),
        postActionRepositoryProvider.overrideWithValue(actions),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: Scaffold(body: ChannelPostsPane(channel: _channel)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectInteractiveCard();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Authoritative refresh'), findsOneWidget);

      actions.realtime.add(
        PostActionPostUpdated(_richPostWithMessage('Late realtime edit')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Late realtime edit'), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: Scaffold(
              body: ThreadPane(
                rootPostId: 'rich-post',
                channel: _channel,
                teamId: 'team',
                onClose: _noop,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectInteractiveCard();

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: LinkedPostPage(
              target: PostNavigationTarget(
                linkedPostId: 'rich-post',
                channelPostId: 'rich-post',
                channel: _channel,
              ),
              stateScopeId: 'permalink-regression',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectInteractiveCard();
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectInteractiveCard() {
  expect(find.text('Release approval'), findsOneWidget);
  expect(find.widgetWithText(ElevatedButton, 'Approve'), findsOneWidget);
}

void _noop() {}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

const SidebarChannel _channel = SidebarChannel(
  id: 'channel',
  teamId: 'team',
  name: 'town-square',
  displayName: 'Town Square',
  kind: ChannelKind.publicChannel,
);

final ChannelPost _richPost = ChannelPost(
  id: 'rich-post',
  channelId: 'channel',
  author: const PostAuthor(id: 'bot', displayName: 'Release bot'),
  sentAt: DateTime(2026),
  message: '',
  richAttachments: const <RichAttachment>[
    RichAttachment(
      title: 'Release approval',
      text: 'Review the **production** deployment.',
      actions: <RichAttachmentAction>[
        RichAttachmentButtonAction(id: 'approve', name: 'Approve'),
      ],
    ),
  ],
);

ChannelPost _richPostWithMessage(String message) => Post(
  id: _richPost.id,
  channelId: _richPost.channelId,
  author: _richPost.author,
  sentAt: _richPost.sentAt,
  message: message,
  richAttachments: _richPost.richAttachments,
);

final class _Posts extends PostRepository {
  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => ChannelPostPage(posts: <ChannelPost>[_richPost]);

  @override
  Future<ChannelPostPage> loadAround({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) async => ChannelPostPage(posts: <ChannelPost>[_richPost]);

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();
}

final class _Threads extends ThreadRepository {
  const _Threads();

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async => MessageThread(
    rootPostId: rootPostId,
    root: _richPost,
    isComplete: true,
    loadedAt: DateTime(2026),
  );

  @override
  Future<void> markRead({
    required AuthSession session,
    required String teamId,
    required String rootPostId,
    required DateTime timestamp,
  }) async {}
}

final class _Actions implements PostActionRepository {
  final StreamController<PostActionRealtimeEvent> realtime =
      StreamController<PostActionRealtimeEvent>.broadcast();

  @override
  Future<PostActionResult> execute({
    required AuthSession session,
    required String postId,
    required String actionId,
    RichAttachmentActionToken? token,
    String? selectedOption,
  }) async => PostActionResult(
    updatedPost: _richPostWithMessage('Authoritative refresh'),
  );

  @override
  Stream<PostActionRealtimeEvent> watchRealtime({
    required AuthSession session,
  }) => realtime.stream;

  Future<void> dispose() => realtime.close();
}
