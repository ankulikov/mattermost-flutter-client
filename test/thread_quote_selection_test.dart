import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/message_thread.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/thread_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/message_actions_strings.dart';
import 'package:mattermost_flutter/src/ui/threads/widgets/thread_pane.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  testWidgets('thread tap opens actions and selected text quotes into reply', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(_session),
          threadRepositoryProvider.overrideWithValue(const _Threads()),
          postRepositoryProvider.overrideWithValue(const _Posts()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ThreadPane(
              rootPostId: 'root',
              channel: _channel,
              onClose: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Finder message = find.text('First line\nSecond line');

    await tester.tap(message, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsOneWidget,
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await tester.longPress(message, kind: PointerDeviceKind.touch);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('message-actions-bottom-sheet')),
      findsNothing,
    );
    expect(find.text(MessageActionsStrings.quote), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MessageActionsStrings.quote));
    await tester.pumpAndSettle();

    final TextField composer = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('message-input-thread-root')),
    );
    expect(composer.controller?.text, '> First line\n> Second line\n\n');
    expect(composer.focusNode?.hasFocus, isTrue);
  });
}

void _noop() {}

final AuthSession _session = AuthSession(
  serverUrl: Uri.parse('https://chat.example.test'),
  userId: 'me',
  username: 'me',
);

const SidebarChannel _channel = SidebarChannel(
  id: 'channel',
  teamId: '',
  name: 'direct',
  displayName: 'Teammate',
  kind: ChannelKind.directMessage,
);

final ChannelPost _root = ChannelPost(
  id: 'root',
  channelId: 'channel',
  author: const PostAuthor(id: 'other', displayName: 'Teammate'),
  sentAt: DateTime(2026),
  message: 'First line\nSecond line',
);

final class _Threads extends ThreadRepository {
  const _Threads();

  @override
  Future<MessageThread> load({
    required AuthSession session,
    required String rootPostId,
  }) async => MessageThread(
    rootPostId: rootPostId,
    root: _root,
    isComplete: true,
    loadedAt: DateTime(2026),
  );
}

final class _Posts extends PostRepository {
  const _Posts();

  @override
  Future<ChannelPostPage> loadLatest({
    required AuthSession session,
    required String channelId,
  }) async => const ChannelPostPage();

  @override
  Future<ChannelPostPage> loadOlder({
    required AuthSession session,
    required String channelId,
    required String beforePostId,
  }) async => const ChannelPostPage();
}
