import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_content.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/rich_attachments.dart';

void main() {
  final Post post = Post(
    id: 'post-1',
    channelId: 'channel-1',
    author: const PostAuthor(id: 'ada', displayName: 'Ada'),
    sentAt: DateTime(2026),
    message: '',
    richAttachments: <RichAttachment>[
      RichAttachment(
        color: '#00aa44',
        pretext: 'Deployment pending',
        authorName: 'Release bot',
        title: 'Deploy production',
        titleLink: '/team/pl/target-post',
        text: 'Choose an **owner**.',
        fields: <RichAttachmentField>[
          RichAttachmentField(
            title: 'Environment',
            value: '@ada',
            isShort: true,
          ),
          RichAttachmentField(
            title: 'Revision',
            value: '`abc123`',
            isShort: true,
          ),
          RichAttachmentField(
            title: 'Details',
            value: 'Visible at every width.',
          ),
        ],
        footer: 'Automation',
        timestamp: DateTime(2026, 1, 2),
        actions: <RichAttachmentAction>[
          RichAttachmentButtonAction(
            id: 'approve',
            name: 'Approve',
            style: RichAttachmentButtonStyle.success,
            tooltip: 'Approve deployment',
          ),
          RichAttachmentSelectAction(
            id: 'owner',
            name: 'Owner',
            defaultOption: 'ada',
            options: <RichAttachmentOption>[
              RichAttachmentOption(text: 'Ada', value: 'ada'),
              RichAttachmentOption(text: 'Grace', value: 'grace'),
            ],
          ),
          RichAttachmentUnknownAction(
            id: 'future',
            name: 'Future action',
            type: 'date_picker',
          ),
        ],
      ),
    ],
  );

  testWidgets('renders a rich card through the shared message content stack', (
    WidgetTester tester,
  ) async {
    await _pump(tester, post);

    expect(find.text('Deployment pending'), findsOneWidget);
    expect(find.text('Release bot'), findsOneWidget);
    expect(find.text('Deploy production'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rich-attachment-Deploy production')),
      findsOneWidget,
    );
  });

  testWidgets('routes title permalink through the shared Markdown callback', (
    WidgetTester tester,
  ) async {
    String? openedPost;
    await _pump(
      tester,
      post,
      onOpenPostLink: (String postId) => openedPost = postId,
    );

    await tester.tap(find.text('Deploy production'));
    await tester.pump();

    expect(openedPost, 'target-post');
  });

  testWidgets('keeps cards usable at compact width with large text', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      post,
      width: 360,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.text('Deploy production'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders controls read-only until an action callback is injected',
    (WidgetTester tester) async {
      await _pump(tester, post);

      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Approve'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Ada'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Future action'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'forwards button and select action values to the injected callback',
    (WidgetTester tester) async {
      final List<(String, String?)> calls = <(String, String?)>[];
      await _pump(
        tester,
        post,
        onAction: (RichAttachmentAction action, String? value) =>
            calls.add((action.id, value)),
      );

      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grace').last);
      await tester.pump();

      expect(calls, <(String, String?)>[('approve', null), ('owner', 'grace')]);
    },
  );

  testWidgets('uses an accessible placeholder for an invalid remote image', (
    WidgetTester tester,
  ) async {
    final Post imagePost = Post(
      id: 'post-image',
      channelId: 'channel-1',
      author: const PostAuthor(id: 'ada', displayName: 'Ada'),
      sentAt: DateTime(2026),
      message: '',
      richAttachments: const <RichAttachment>[
        RichAttachment(title: 'Image', imageUrl: 'file:///private/image.png'),
      ],
    );
    await _pump(
      tester,
      imagePost,
      width: 360,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Post post, {
  ValueChanged<String>? onOpenPostLink,
  RichAttachmentActionCallback? onAction,
  double width = 800,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MessageContent(
                  post: post,
                  serverUrl: Uri.parse('https://chat.example.test'),
                  onOpenPostLink: onOpenPostLink,
                  onRichAttachmentAction: onAction,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
