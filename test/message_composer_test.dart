import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';
import 'package:mattermost_flutter/src/ui/messages/message_composer_strings.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_composer.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';

import 'support/fake_emoji_repository.dart';

void main() {
  test('formats every selected line as a Markdown quote', () {
    expect(
      formatMarkdownQuote('First line\r\nSecond line\n'),
      '> First line\n> Second line\n> ',
    );
  });

  testWidgets('composer controller inserts a multiline quote and focuses', (
    WidgetTester tester,
  ) async {
    final MessageComposerController composerController =
        MessageComposerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'thread-1',
            placeholder: 'Reply',
            composerController: composerController,
            onSubmit: (_, _) async {},
          ),
        ),
      ),
    );
    final Finder input = find.byKey(
      const ValueKey<String>('message-input-thread-1'),
    );
    await tester.enterText(input, 'Existing draft');

    composerController.insertQuote('First line\nSecond line');
    await tester.pump();

    final TextField field = tester.widget<TextField>(input);
    expect(
      field.controller?.text,
      'Existing draft\n> First line\n> Second line\n\n',
    );
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets(
    'edits a post, preserves the draft, and keeps changes on failure',
    (WidgetTester tester) async {
      final controller = MessageComposerController();
      final edits = <String>[];
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'channel-1',
              placeholder: 'Message channel',
              composerController: controller,
              onSubmit: (_, _) async {},
              onEdit: (postId, message) async {
                edits.add('$postId:$message');
                attempts += 1;
                if (attempts == 1) throw StateError('offline');
              },
            ),
          ),
        ),
      );
      final input = find.byKey(
        const ValueKey<String>('message-input-channel-1'),
      );
      final save = find.byKey(const ValueKey<String>('send-message-channel-1'));
      await tester.enterText(input, 'Unsent draft');
      controller.editPost(postId: 'root-1', message: 'Old **text**');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, 'Old **text**');
      expect(find.text(MessageComposerStrings.editing), findsOneWidget);

      await tester.enterText(input, 'New **text**');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(MessageComposerStrings.editFailed), findsOneWidget);
      expect(tester.widget<TextField>(input).controller?.text, 'New **text**');

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(edits, <String>['root-1:New **text**', 'root-1:New **text**']);
      expect(tester.widget<TextField>(input).controller?.text, 'Unsent draft');
      expect(find.text(MessageComposerStrings.editing), findsNothing);
      expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);
    },
  );

  testWidgets('rich editor saves an edited message and cancel restores draft', (
    WidgetTester tester,
  ) async {
    final controller = MessageComposerController();
    String? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'thread-1',
            placeholder: 'Reply',
            composerController: controller,
            onSubmit: (_, _) async {},
            onEdit: (postId, message) async => edited = '$postId:$message',
          ),
        ),
      ),
    );
    final input = find.byKey(const ValueKey<String>('message-input-thread-1'));
    await tester.enterText(input, 'Reply draft');
    controller.editPost(postId: 'root-1', message: 'Original');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('open-full-editor-thread-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text(MessageComposerStrings.editing), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey<String>('full-message-input-thread-1')),
      '**Updated**',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('full-editor-send-thread-1')),
    );
    await tester.pumpAndSettle();
    expect(edited, 'root-1:**Updated**');
    expect(tester.widget<TextField>(input).controller?.text, 'Reply draft');
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);

    controller.editPost(postId: 'root-2', message: 'Another');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('cancel-message-edit')));
    await tester.pump();
    expect(tester.widget<TextField>(input).controller?.text, 'Reply draft');
  });

  for (final width in <double>[320, 1200]) {
    testWidgets('edit composer fits ${width.toInt()}px with large text', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MessageComposerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.7)),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: MessageComposer(
                  destinationId: 'channel-1',
                  placeholder: 'Message channel',
                  composerController: controller,
                  onSubmit: (_, _) async {},
                  onEdit: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      );
      controller.editPost(postId: 'root-1', message: 'Original text');
      await tester.pump();
      expect(find.text(MessageComposerStrings.editing), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey<String>('message-input-channel-1')),
            )
            .controller
            ?.text,
        'Original text',
      );
      expect(tester.takeException(), isNull);
    });
  }

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
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isTrue);

    await tester.tap(send);
    await tester.pump();

    expect(pendingIds, hasLength(2));
    expect(pendingIds[1], pendingIds[0]);
    expect(find.text('Keep this draft'), findsNothing);
    expect(find.text(MessageComposerStrings.sendFailed), findsNothing);
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);
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

  testWidgets('send button finalizes an active Android composing region', (
    WidgetTester tester,
  ) async {
    final Completer<void> completion = Completer<void>();
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'android-composing',
            placeholder: 'Message channel',
            onSubmit: (String message, String pendingPostId) {
              submitted = message;
              return completion.future;
            },
          ),
        ),
      ),
    );

    final Finder input = find.byKey(
      const ValueKey<String>('message-input-android-composing'),
    );
    await tester.enterText(input, 'Send this word');
    final TextEditingController controller = tester
        .widget<TextField>(input)
        .controller!;
    controller.value = controller.value.copyWith(
      selection: const TextSelection.collapsed(offset: 14),
      composing: const TextRange(start: 10, end: 14),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(submitted, isNull);
    expect(controller.value.composing, const TextRange(start: 10, end: 14));

    await tester.tap(
      find.byKey(const ValueKey<String>('send-message-android-composing')),
    );
    await tester.pump();

    expect(submitted, 'Send this word');
    expect(controller.value.composing, TextRange.empty);

    completion.complete();
    await tester.pump();
    expect(tester.widget<TextField>(input).focusNode?.hasFocus, isFalse);
  });

  for (final double width in <double>[320, 900]) {
    testWidgets(
      'adapts composer controls at ${width.toInt()}px with large text',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(Size(width, 400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: MessageComposer(
                  destinationId: 'adaptive',
                  placeholder: 'Write a message',
                  onSubmit: (String message, String pendingPostId) async {},
                ),
              ),
            ),
          ),
        );

        final Finder input = find.byKey(
          const ValueKey<String>('message-input-adaptive'),
        );
        final Finder fullEditor = find.byKey(
          const ValueKey<String>('open-full-editor-adaptive'),
        );
        final Finder send = find.byKey(
          const ValueKey<String>('send-message-adaptive'),
        );
        if (width < 700) {
          expect(tester.getSize(input).width, moreOrLessEquals(width - 44));
          expect(
            tester.getTopLeft(fullEditor).dy,
            greaterThan(tester.getBottomLeft(input).dy),
          );
          expect(
            tester.getTopLeft(send).dy,
            greaterThan(tester.getBottomLeft(input).dy),
          );
        } else {
          expect(tester.getSize(input).width, lessThan(width - 44));
          expect(
            tester.getBottomLeft(fullEditor).dy,
            moreOrLessEquals(tester.getBottomLeft(input).dy),
          );
          expect(
            tester.getBottomLeft(send).dy,
            moreOrLessEquals(tester.getBottomLeft(input).dy),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('keeps suggestions open for Android composing text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _emojiComposerApp(repository: FakeEmojiRepository()),
    );
    final Finder input = find.byKey(
      const ValueKey<String>('message-input-emoji'),
    );
    final TextEditingController controller = tester
        .widget<TextField>(input)
        .controller!;

    await tester.enterText(input, ':of');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('composer-emoji-suggestions')),
      findsOneWidget,
    );

    controller.value = controller.value.copyWith(
      composing: const TextRange(start: 1, end: 3),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('composer-emoji-suggestions')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('emoji-office')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('emoji-office')));
    await tester.pump();
    expect(controller.text, '🏢');
    expect(controller.value.composing, TextRange.empty);
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

  testWidgets('selects a group mention and submits its unchanged handle', (
    WidgetTester tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'group-mention',
            placeholder: 'Write a message',
            accountId: 'account-a',
            teamId: 'team-1',
            channelId: 'channel-1',
            mentionRepositoryFactory: _GroupMentionRepository.new,
            onSubmit: (String message, String pendingPostId) async {
              submitted = message;
            },
          ),
        ),
      ),
    );

    final Finder input = find.byKey(
      const ValueKey<String>('message-input-group-mention'),
    );
    await tester.enterText(input, '@back');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    final Finder group = find.byKey(
      const ValueKey<String>('mention-group-backend-id'),
    );
    expect(group, findsOneWidget);
    await tester.tap(group);
    await tester.pump();

    expect(tester.widget<TextField>(input).controller?.text, '\uFFFC ');
    await tester.tap(
      find.byKey(const ValueKey<String>('send-message-group-mention')),
    );
    await tester.pump();

    expect(submitted, '@backend ');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'quick composer opens the full editor and preserves its formatted draft',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'formatting',
              placeholder: 'Write a message',
              onSubmit: (String message, String pendingPostId) async {},
            ),
          ),
        ),
      );
      final Finder input = find.byKey(
        const ValueKey<String>('message-input-formatting'),
      );
      expect(
        find.byKey(const ValueKey<String>('message-formatting-bold')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('open-full-editor-formatting')),
        findsOneWidget,
      );
      await tester.enterText(input, 'format me');
      await tester.tap(
        find.byKey(const ValueKey<String>('open-full-editor-formatting')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('full-editor-modal')),
        findsOneWidget,
      );
      final Finder fullInput = find.byKey(
        const ValueKey<String>('full-message-input-formatting'),
      );
      final TextEditingController controller = tester
          .widget<TextField>(fullInput)
          .controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 9,
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('message-formatting-bold')),
      );
      await tester.pump();

      expect(controller.text, '**format me**');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 11),
      );
      expect(tester.widget<TextField>(fullInput).focusNode?.hasFocus, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('close-full-editor')));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(input).controller?.text, '**format me**');
    },
  );

  testWidgets('full editor link control formats the selected label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'link-formatting',
            placeholder: 'Write a message',
            onSubmit: (_, _) async {},
          ),
        ),
      ),
    );
    final Finder quickInput = find.byKey(
      const ValueKey<String>('message-input-link-formatting'),
    );
    await tester.enterText(quickInput, 'Mattermost');
    await tester.tap(
      find.byKey(const ValueKey<String>('open-full-editor-link-formatting')),
    );
    await tester.pumpAndSettle();

    final Finder fullInput = find.byKey(
      const ValueKey<String>('full-message-input-link-formatting'),
    );
    final TextEditingController controller = tester
        .widget<TextField>(fullInput)
        .controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('message-formatting-link')),
    );
    await tester.pump();

    expect(controller.text, '[Mattermost](url)');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 11),
    );
    expect(tester.widget<TextField>(fullInput).focusNode?.hasFocus, isTrue);
  });

  testWidgets(
    'full editor searches emoji and Enter inserts instead of sending',
    (WidgetTester tester) async {
      final FakeEmojiRepository repository = FakeEmojiRepository();
      final List<String> submissions = <String>[];
      await tester.pumpWidget(
        _emojiComposerApp(
          repository: repository,
          onSubmit: (String message, String _) async {
            submissions.add(message);
          },
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('message-input-emoji')),
        'Meet :of',
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('open-full-editor-emoji')),
      );
      await tester.pumpAndSettle();
      final Finder input = find.byKey(
        const ValueKey<String>('full-message-input-emoji'),
      );

      expect(
        find.byKey(const ValueKey<String>('full-editor-emoji-suggestions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('emoji-office')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submissions, isEmpty);
      expect(tester.widget<TextField>(input).controller?.text, 'Meet 🏢');

      await tester.tap(
        find.byKey(const ValueKey<String>('full-editor-send-emoji')),
      );
      await tester.pumpAndSettle();
      expect(submissions, <String>['Meet 🏢']);
    },
  );

  testWidgets(
    'compact full editor searches and inserts people and user groups',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final List<String> submissions = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 760),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: MessageComposer(
                  destinationId: 'full-mentions',
                  placeholder: 'Write a message',
                  accountId: 'account-a',
                  teamId: 'team-1',
                  channelId: 'channel-1',
                  mentionRepositoryFactory:
                      _PeopleAndGroupsMentionRepository.new,
                  onSubmit: (String message, String _) async {
                    submissions.add(message);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      Future<Finder> openEditorAndSearch(String query) async {
        await tester.tap(
          find.byKey(const ValueKey<String>('open-full-editor-full-mentions')),
        );
        await tester.pumpAndSettle();
        final Finder input = find.byKey(
          const ValueKey<String>('full-message-input-full-mentions'),
        );
        await tester.enterText(input, query);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(
          find.byKey(const ValueKey<String>('full-editor-mention-suggestions')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        return input;
      }

      await openEditorAndSearch('@be');
      expect(
        find.byKey(const ValueKey<String>('mention-bea-id')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('mention-group-backend-id')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('mention-bea-id')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('full-editor-send-full-mentions')),
      );
      await tester.pumpAndSettle();
      expect(submissions, <String>['@bea ']);

      await openEditorAndSearch('@back');
      await tester.tap(
        find.byKey(const ValueKey<String>('mention-group-backend-id')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('full-editor-send-full-mentions')),
      );
      await tester.pumpAndSettle();

      expect(submissions, <String>['@bea ', '@backend ']);
      expect(tester.takeException(), isNull);
    },
  );

  for (final double width in <double>[320, 900]) {
    testWidgets(
      'full editor adapts and keeps every formatting icon visible at $width',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(Size(width, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 760),
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(
                body: MessageComposer(
                  destinationId: 'adaptive-editor',
                  placeholder: 'Write a message',
                  onSubmit: (_, _) async {},
                ),
              ),
            ),
          ),
        );

        await tester.tap(
          find.byKey(
            const ValueKey<String>('open-full-editor-adaptive-editor'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            ValueKey<String>(
              width < 700 ? 'full-editor-fullscreen' : 'full-editor-modal',
            ),
          ),
          findsOneWidget,
        );
        for (final MessageFormattingCommand command
            in MessageFormattingCommand.values) {
          expect(
            find.byKey(ValueKey<String>('message-formatting-${command.name}')),
            findsOneWidget,
          );
        }
        expect(
          find.byKey(const ValueKey<String>('message-formatting-overflow')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('full editor keeps a failed draft and closes after retry', (
    WidgetTester tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageComposer(
            destinationId: 'full-retry',
            placeholder: 'Write a message',
            onSubmit: (_, _) async {
              attempts += 1;
              if (attempts == 1) throw StateError('offline');
            },
          ),
        ),
      ),
    );
    final Finder quickInput = find.byKey(
      const ValueKey<String>('message-input-full-retry'),
    );
    await tester.enterText(quickInput, 'Keep this draft');
    await tester.tap(
      find.byKey(const ValueKey<String>('open-full-editor-full-retry')),
    );
    await tester.pumpAndSettle();

    final Finder fullInput = find.byKey(
      const ValueKey<String>('full-message-input-full-retry'),
    );
    final Finder send = find.byKey(
      const ValueKey<String>('full-editor-send-full-retry'),
    );
    await tester.tap(send);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('full-editor-send-error-full-retry')),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(fullInput).controller?.text,
      'Keep this draft',
    );
    expect(tester.widget<TextField>(fullInput).focusNode?.hasFocus, isTrue);

    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey<String>('full-editor-modal')),
      findsNothing,
    );
    expect(tester.widget<TextField>(quickInput).controller?.text, isEmpty);
  });

  testWidgets(
    'Ctrl+B and Ctrl+I apply formatting when autocomplete and IME are idle',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'shortcuts',
              placeholder: 'Write a message',
              onSubmit: (String message, String pendingPostId) async {},
            ),
          ),
        ),
      );
      final Finder input = find.byKey(
        const ValueKey<String>('message-input-shortcuts'),
      );
      await tester.enterText(input, 'text');
      final TextEditingController controller = tester
          .widget<TextField>(input)
          .controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.text, '**text**');

      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.text, '***text***');
    },
  );

  testWidgets(
    'Shift+Enter continues and exits Markdown list and quote blocks',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageComposer(
              destinationId: 'blocks',
              placeholder: 'Write a message',
              onSubmit: (String message, String pendingPostId) async {},
            ),
          ),
        ),
      );
      final Finder input = find.byKey(
        const ValueKey<String>('message-input-blocks'),
      );
      await tester.enterText(input, '- item');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '- item\n- ');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '- item\n');

      await tester.enterText(input, '> quoted');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '> quoted\n> ');
    },
  );
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

final class _GroupMentionRepository implements MentionRepository {
  @override
  Future<MentionSearchResult> autocomplete({
    required String teamId,
    required String channelId,
    required String term,
    int limit = 30,
  }) async => const MentionSearchResult(
    channelMembers: <MentionCandidate>[],
    groupMentions: <GroupMentionCandidate>[
      GroupMentionCandidate(
        group: GroupMention(
          id: 'backend-id',
          name: 'backend',
          displayName: 'Backend Team',
          memberCount: 18,
        ),
      ),
    ],
    notInChannel: <MentionCandidate>[],
  );

  @override
  Future<List<GroupMention>> resolveGroupsByNames(List<String> names) async =>
      const <GroupMention>[];
}

final class _PeopleAndGroupsMentionRepository implements MentionRepository {
  @override
  Future<MentionSearchResult> autocomplete({
    required String teamId,
    required String channelId,
    required String term,
    int limit = 30,
  }) async => const MentionSearchResult(
    channelMembers: <MentionCandidate>[
      MentionCandidate(
        user: UserSummary(
          id: 'bea-id',
          firstName: 'Bea',
          lastName: 'Developer',
          username: 'bea',
          nickname: '',
          position: '',
          email: '',
        ),
      ),
    ],
    groupMentions: <GroupMentionCandidate>[
      GroupMentionCandidate(
        group: GroupMention(
          id: 'backend-id',
          name: 'backend',
          displayName: 'Backend Team',
          memberCount: 18,
        ),
      ),
    ],
    notInChannel: <MentionCandidate>[],
  );

  @override
  Future<List<GroupMention>> resolveGroupsByNames(List<String> names) async =>
      const <GroupMention>[];
}
