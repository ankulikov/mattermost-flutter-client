import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_action_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri(scheme: 'https', host: 'chat.example.test'),
    userId: 'me',
    username: 'me',
  );
  final Post post = Post(
    id: 'post',
    channelId: 'channel',
    author: const PostAuthor(id: 'bot', displayName: 'Bot'),
    sentAt: DateTime(2026),
    message: '',
    richAttachments: const <RichAttachment>[
      RichAttachment(
        title: 'Approval',
        actions: <RichAttachmentAction>[
          RichAttachmentButtonAction(id: 'approve', name: 'Approve'),
          RichAttachmentButtonAction(id: 'reject', name: 'Reject'),
        ],
      ),
    ],
  );

  testWidgets('shows ephemeral feedback only beside the initiating control', (
    WidgetTester tester,
  ) async {
    final _Repository repository = _Repository(post);
    addTearDown(repository.dispose);
    final List<ChannelPost> updates = <ChannelPost>[];
    String? destination;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          postActionRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageContent(
              post: post,
              actionScopeId: 'screen',
              onRichAttachmentAction: (_, _) {},
              onRichAttachmentPostUpdated: updates.add,
              onRichAttachmentGotoLocation: (String value) =>
                  destination = value,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pump();
    expect(find.text('Approval'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Approve'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reject'))
          .onPressed,
      isNotNull,
    );
    repository.realtime.add(
      const PostActionEphemeralFeedback(
        channelId: 'channel',
        sourceRootPostId: 'post',
        message: 'Deployment approved',
      ),
    );
    await tester.pump();

    expect(find.text('Deployment approved'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Reject'))
          .onPressed,
      isNotNull,
    );

    final ChannelPost refreshed = Post(
      id: 'post',
      channelId: 'channel',
      author: const PostAuthor(id: 'bot', displayName: 'Bot'),
      sentAt: DateTime(2026),
      message: 'Authoritative refresh',
    );
    repository.complete(updatedPost: refreshed, gotoLocation: '/team/pl/next');
    await tester.pump();
    expect(updates.single.message, 'Authoritative refresh');
    expect(destination, '/team/pl/next');

    final ChannelPost realtimeEdit = Post(
      id: 'post',
      channelId: 'channel',
      author: const PostAuthor(id: 'bot', displayName: 'Bot'),
      sentAt: DateTime(2026),
      message: 'Late realtime edit',
    );
    repository.realtime.add(PostActionPostUpdated(realtimeEdit));
    await tester.pump();
    expect(updates.last.message, 'Late realtime edit');
  });

  testWidgets('keeps the card and re-enables its control after failure', (
    WidgetTester tester,
  ) async {
    final _Repository repository = _Repository(post);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(session),
          postActionRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageContent(
              post: post,
              actionScopeId: 'screen',
              onRichAttachmentAction: (_, _) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pump();
    repository.fail();
    await tester.pump();

    expect(find.text('Approval'), findsOneWidget);
    expect(find.text('Action failed. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Approve'),
          )
          .onPressed,
      isNotNull,
    );
  });
}

final class _Repository implements PostActionRepository {
  _Repository(this.post);

  final Post post;
  final StreamController<PostActionRealtimeEvent> realtime =
      StreamController<PostActionRealtimeEvent>.broadcast();
  final Completer<PostActionResult> _result = Completer<PostActionResult>();

  @override
  Future<PostActionResult> execute({
    required AuthSession session,
    required String postId,
    required String actionId,
    RichAttachmentActionToken? token,
    String? selectedOption,
  }) => _result.future;

  @override
  Stream<PostActionRealtimeEvent> watchRealtime({
    required AuthSession session,
  }) => realtime.stream;

  void complete({ChannelPost? updatedPost, String gotoLocation = ''}) {
    if (!_result.isCompleted) {
      _result.complete(
        PostActionResult(
          updatedPost: updatedPost ?? post,
          gotoLocation: gotoLocation,
        ),
      );
    }
  }

  void fail() {
    if (!_result.isCompleted) {
      _result.completeError(StateError('action failed'));
    }
  }

  Future<void> dispose() => realtime.close();
}
