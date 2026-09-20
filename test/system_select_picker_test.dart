import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment_option.dart';
import 'package:mattermost_flutter/src/domain/repositories/rich_attachment_option_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/rich_attachments.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

void main() {
  final AuthSession session = AuthSession(
    serverUrl: Uri(scheme: 'https', host: 'chat.example.test'),
    userId: 'me',
    username: 'me',
  );

  testWidgets('searches, cancels the superseded query, and submits user ID', (
    WidgetTester tester,
  ) async {
    final _Options repository = _Options();
    String? selected;
    await _pump(
      tester,
      session: session,
      repository: repository,
      onAction: (_, String? value) => selected = value,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Owner'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ada');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(repository.firstCancelled, isTrue);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
    expect(selected, 'user-ada');
  });

  testWidgets('shows error and empty states without closing the picker', (
    WidgetTester tester,
  ) async {
    final _Options repository = _Options(failInitial: true);
    await _pump(
      tester,
      session: session,
      repository: repository,
      onAction: (_, _) {},
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Owner'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load options.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'none');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('No matching options'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required AuthSession session,
  required RichAttachmentOptionRepository repository,
  required RichAttachmentActionCallback onAction,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authSessionProvider.overrideWithValue(session),
      richAttachmentOptionRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: MessageContent(
          post: Post(
            id: 'post',
            channelId: 'channel',
            author: const PostAuthor(id: 'bot', displayName: 'Bot'),
            sentAt: DateTime(2026),
            message: '',
            richAttachments: const <RichAttachment>[
              RichAttachment(
                title: 'Assign',
                actions: <RichAttachmentAction>[
                  RichAttachmentSelectAction(
                    id: 'owner',
                    name: 'Owner',
                    dataSource: RichAttachmentSelectDataSource.users,
                  ),
                ],
              ),
            ],
          ),
          onRichAttachmentAction: onAction,
        ),
      ),
    ),
  ),
);

final class _Options implements RichAttachmentOptionRepository {
  _Options({this.failInitial = false});

  final bool failInitial;
  bool firstCancelled = false;

  @override
  Future<List<RichAttachmentSystemOption>> search({
    required AuthSession session,
    required RichAttachmentSelectDataSource dataSource,
    required String query,
    int limit = 30,
  }) {
    if (query.isEmpty && failInitial) {
      return Future<List<RichAttachmentSystemOption>>.error(
        StateError('offline'),
      );
    }
    if (query.isEmpty) {
      final Completer<List<RichAttachmentSystemOption>> completer =
          Completer<List<RichAttachmentSystemOption>>();
      RequestCancellation.current!.addListener((_) {
        firstCancelled = true;
        completer.completeError(const RequestCancelledException('new query'));
      });
      return completer.future;
    }
    if (query == 'ada') {
      return Future<List<RichAttachmentSystemOption>>.value(
        const <RichAttachmentSystemOption>[
          RichAttachmentSystemOption(
            value: 'user-ada',
            label: 'Ada Lovelace',
            description: '@ada',
          ),
        ],
      );
    }
    return Future<List<RichAttachmentSystemOption>>.value(
      const <RichAttachmentSystemOption>[],
    );
  }
}
