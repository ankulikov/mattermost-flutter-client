import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';

import 'support/fake_emoji_repository.dart';

void main() {
  testWidgets('keeps a failed draft and reuses its pending post id', (
    WidgetTester tester,
  ) async {
    final List<String> pendingIds = <String>[];
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'channel-1',
            placeholder: 'Message channel',
            onSubmit: (String message, String pendingPostId) async {
              pendingIds.add(pendingPostId);
              attempts += 1;
              if (attempts == 1) throw StateError('offline');
            },
          ),
        ),
      ),
    );

    final Finder input = find.byKey(
      const ValueKey<String>('message-input-channel-1'),
    );
    final Finder send = find.byKey(
      const ValueKey<String>('send-message-channel-1'),
    );
    await tester.enterText(input, 'Keep this draft');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();

    expect(find.text('Keep this draft'), findsOneWidget);
    expect(find.text(MessageComposerStrings.sendFailed), findsOneWidget);

    await tester.tap(send);
    await tester.pump();

    expect(pendingIds, hasLength(2));
    expect(pendingIds[1], pendingIds[0]);
    expect(find.text('Keep this draft'), findsNothing);
    expect(find.text(MessageComposerStrings.sendFailed), findsNothing);
  });

  testWidgets(
    'Enter sends, Shift+Enter adds a line, and send is single-flight',
    (WidgetTester tester) async {
      final Completer<void> completion = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'channel-1',
              placeholder: 'Message channel',
              onSubmit: (String message, String pendingPostId) {
                calls += 1;
                return completion.future;
              },
            ),
          ),
        ),
      );

      final Finder input = find.byKey(
        const ValueKey<String>('message-input-channel-1'),
      );
      await tester.enterText(input, 'Send with Enter');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(calls, 0);
      expect(
        tester.widget<TextField>(input).controller?.text,
        'Send with Enter\n',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completion.complete();
      await tester.pump();
      expect(find.text('Send with Enter'), findsNothing);
    },
  );

  testWidgets('lays out at compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: MessageComposer(
              destinationId: 'compact',
              placeholder: 'Write a message',
              onSubmit: (String message, String pendingPostId) async {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('opens after two characters and inserts a system emoji', (
    WidgetTester tester,
  ) async {
    final FakeEmojiRepository repository = FakeEmojiRepository();
    String? submitted;
    await tester.pumpWidget(
      _emojiComposerApp(
        repository: repository,
        onSubmit: (String message, String _) async => submitted = message,
      ),
    );
    final Finder input = find.byKey(
      const ValueKey<String>('message-input-emoji'),
    );

    await tester.enterText(input, 'Meet :o');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('composer-emoji-suggestions')),
      findsNothing,
    );

    await tester.enterText(input, 'Meet :of');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('composer-emoji-suggestions')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('emoji-office')), findsOneWidget);

    await tester.enterText(input, 'Meet :cof');
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('emoji-office')), findsNothing);
    expect(find.byKey(const ValueKey<String>('emoji-coffee')), findsOneWidget);

    await tester.enterText(input, 'Meet :of');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('emoji-office')));
    await tester.pump();
    expect(tester.widget<TextField>(input).controller?.text, 'Meet 🏢');
    expect(
      find.byKey(const ValueKey<String>('composer-emoji-suggestions')),
      findsNothing,
    );
    expect(repository.remembered, <String>['office']);

    await tester.tap(find.byKey(const ValueKey<String>('send-message-emoji')));
    await tester.pump();
    expect(submitted, 'Meet 🏢');
  });

  testWidgets('mouse press keeps suggestions alive until tap selects emoji', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _emojiComposerApp(repository: FakeEmojiRepository()),
    );
    final Finder input = find.byKey(
      const ValueKey<String>('message-input-emoji'),
    );
    final Finder emoji = find.byKey(const ValueKey<String>('emoji-smiley'));
    await tester.enterText(input, 'How are you? :sm');
    await tester.pump();
    expect(emoji, findsOneWidget);

    final TestGesture mouse = await tester.startGesture(
      tester.getCenter(emoji),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(tester.widget<TextField>(input).controller?.text, 'How are you? 😃');
  });

  testWidgets('renders a selected custom emoji and submits its shortcode', (
    WidgetTester tester,
  ) async {
    MethodCall? clipboardCall;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final FakeEmojiRepository repository = FakeEmojiRepository()
      ..searchResults = const <CustomEmojiReference>[
        CustomEmojiReference(
          name: 'party_parrot',
          id: 'custom-1',
          updatedAt: 4,
        ),
      ];
    String? submitted;
    await tester.pumpWidget(
      _emojiComposerApp(
        repository: repository,
        onSubmit: (String message, String _) async => submitted = message,
      ),
    );
    final Finder input = find.byKey(
      const ValueKey<String>('message-input-emoji'),
    );

    await tester.enterText(input, 'Look :party_p');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(repository.searchedTerms, <String>['party_p']);
    expect(
      find.byKey(const ValueKey<String>('emoji-party_parrot')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('emoji-party_parrot')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('composer-custom-emoji-party_parrot')),
      findsOneWidget,
    );

    final TextEditingController controller = tester
        .widget<TextField>(input)
        .controller!;
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, <String, Object>{
      'text': 'Look :party_parrot:',
    });

    await tester.tap(find.byKey(const ValueKey<String>('send-message-emoji')));
    await tester.pump();
    expect(submitted, 'Look :party_parrot:');
  });

  testWidgets('Enter chooses the highlighted emoji instead of submitting', (
    WidgetTester tester,
  ) async {
    var submissions = 0;
    await tester.pumpWidget(
      _emojiComposerApp(
        repository: FakeEmojiRepository(),
        onSubmit: (String message, String _) async => submissions += 1,
      ),
    );
    final Finder input = find.byKey(
      const ValueKey<String>('message-input-emoji'),
    );
    await tester.enterText(input, ':of');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(submissions, 0);
    expect(tester.widget<TextField>(input).controller?.text, '🏢');
  });

  for (final double width in <double>[320, 900]) {
    testWidgets('emoji results fit ${width.toInt()}px with large text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _emojiComposerApp(repository: FakeEmojiRepository()),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('message-input-emoji')),
        ':of',
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('composer-emoji-suggestions')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _emojiComposerApp({
  required FakeEmojiRepository repository,
  SubmitMessage? onSubmit,
}) => MaterialApp(
  home: Scaffold(
    body: MessageComposer(
      destinationId: 'emoji',
      placeholder: 'Write a message',
      emojiRepositoryFactory: () => repository,
      accountId: 'account-a',
      onSubmit: onSubmit ?? (String message, String pendingPostId) async {},
    ),
  ),
);
