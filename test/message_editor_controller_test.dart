import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/message_editor_mode.dart';
import 'package:mattermost_flutter/src/ui/messages/message_editor_controller.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';

void main() {
  group('findEmojiAutocompleteQuery', () {
    test('requires two shortcode characters at a token boundary', () {
      expect(_query(':o'), isNull);
      expect(_query('12:30'), isNull);
      expect(_query('word:of'), isNull);

      final EmojiAutocompleteQuery? result = _query('Say :of');
      expect(result?.term, 'of');
      expect(result?.range, const TextRange(start: 4, end: 7));
    });

    test('ignores completed and selected text', () {
      expect(_query(':office:'), isNull);
      expect(
        findEmojiAutocompleteQuery(
          const TextEditingValue(
            text: ':of',
            selection: TextSelection(baseOffset: 1, extentOffset: 3),
          ),
        ),
        isNull,
      );
    });

    test('accepts a shortcode inside an Android composing region', () {
      final EmojiAutocompleteQuery? result = findEmojiAutocompleteQuery(
        const TextEditingValue(
          text: 'Say :of',
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 5, end: 7),
        ),
      );

      expect(result?.term, 'of');
      expect(result?.range, const TextRange(start: 4, end: 7));
    });

    test('replaces the whole shortcode when the caret is inside it', () {
      final EmojiAutocompleteQuery? result = findEmojiAutocompleteQuery(
        const TextEditingValue(
          text: 'Say :office: now',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );

      expect(result?.term, 'of');
      expect(result?.range, const TextRange(start: 4, end: 12));
    });
  });

  test('custom emoji stays editable and serializes to a shortcode', () {
    final MessageEditorController controller = MessageEditorController(
      customEmojiBuilder: (_, _) => const SizedBox.shrink(),
    );
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'Look :pa',
      selection: TextSelection.collapsed(offset: 8),
    );

    controller.replaceQueryWithCustomEmoji(
      controller.emojiAutocompleteQuery!,
      const CustomEmojiReference(name: 'party_parrot'),
    );

    expect(controller.text, 'Look \uFFFC');
    expect(controller.messageText, 'Look :party_parrot:');
    expect(
      controller.messageTextForRange(const TextRange(start: 5, end: 6)),
      ':party_parrot:',
    );

    controller.value = controller.value.copyWith(
      text: 'Now ${controller.text}',
      selection: const TextSelection.collapsed(offset: 10),
    );
    expect(controller.messageText, 'Now Look :party_parrot:');

    controller.value = controller.value.copyWith(
      text: 'Now Look ',
      selection: const TextSelection.collapsed(offset: 9),
    );
    expect(controller.messageText, 'Now Look ');
  });

  test('mention is an atomic display object and serializes to username', () {
    final MessageEditorController controller = MessageEditorController(
      customEmojiBuilder: (_, _) => const SizedBox.shrink(),
      userMentionBuilder: (_, UserMention mention) =>
          Text('@${mention.displayName}'),
    );
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'Hi @and',
      selection: TextSelection.collapsed(offset: 7),
    );

    controller.replaceQueryWithMention(
      const MentionQuery(
        start: 3,
        end: 7,
        trigger: '@',
        term: 'and',
        key: 'and',
      ),
      const UserMention(
        userId: 'u1',
        username: 'andrey',
        displayName: 'Andrey Kulikov',
      ),
    );

    expect(controller.text, 'Hi \uFFFC ');
    expect(controller.messageText, 'Hi @andrey ');
    expect(
      controller.messageTextForRange(const TextRange(start: 3, end: 4)),
      '@andrey',
    );

    controller.value = controller.value.copyWith(
      text: 'Say ${controller.text}',
      selection: const TextSelection.collapsed(offset: 8),
    );
    expect(controller.messageText, 'Say Hi @andrey ');

    controller.value = controller.value.copyWith(
      text: 'Say Hi ',
      selection: const TextSelection.collapsed(offset: 7),
    );
    expect(controller.messageText, 'Say Hi ');
  });

  test('backspace removes a mention and its automatic trailing separator', () {
    final MessageEditorController controller = MessageEditorController(
      customEmojiBuilder: (_, _) => const SizedBox.shrink(),
    );
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: '@an',
      selection: TextSelection.collapsed(offset: 3),
    );
    controller.replaceQueryWithMention(
      const MentionQuery(start: 0, end: 3, trigger: '@', term: 'an', key: 'an'),
      const UserMention(
        userId: 'u1',
        username: 'andrey',
        displayName: 'Andrey Kulikov',
      ),
    );

    controller.value = controller.value.copyWith(
      text: ' ',
      selection: const TextSelection.collapsed(offset: 0),
    );

    expect(controller.text, isEmpty);
    expect(controller.messageText, isEmpty);
  });

  test('group mention keeps its handle and serializes unchanged', () {
    final MessageEditorController controller = MessageEditorController(
      customEmojiBuilder: (_, _) => const SizedBox.shrink(),
      groupMentionBuilder: (_, GroupMention mention) =>
          Text('@${mention.name}'),
    );
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'Hi @back',
      selection: TextSelection.collapsed(offset: 8),
    );

    controller.replaceQueryWithGroupMention(
      const MentionQuery(
        start: 3,
        end: 8,
        trigger: '@',
        term: 'back',
        key: 'back',
      ),
      const GroupMention(
        id: 'group-1',
        name: 'backend',
        displayName: 'Backend Team',
        memberCount: 18,
      ),
    );

    expect(controller.text, 'Hi \uFFFC ');
    expect(controller.messageText, 'Hi @backend ');
    expect(
      controller.messageTextForRange(const TextRange(start: 3, end: 4)),
      '@backend',
    );

    controller.value = controller.value.copyWith(
      text: 'Hi ',
      selection: const TextSelection.collapsed(offset: 3),
    );
    expect(controller.text, 'Hi ');
  });

  testWidgets(
    'live preview collapses only inactive markers without changing raw text',
    (WidgetTester tester) async {
      final MessageEditorController controller = MessageEditorController(
        customEmojiBuilder: (_, _) => const SizedBox.shrink(),
      );
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: '**test** ',
        selection: TextSelection.collapsed(offset: 9),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );

      TextSpan span = controller.buildTextSpan(
        context: context,
        withComposing: true,
      );
      expect(span.toPlainText(), controller.text);
      expect(controller.messageText, '**test** ');
      expect(_spans(span).where(_isCollapsedMarker), hasLength(2));

      controller.selection = const TextSelection.collapsed(offset: 3);
      span = controller.buildTextSpan(context: context, withComposing: true);
      expect(span.toPlainText(), controller.text);
      expect(_spans(span).where(_isCollapsedMarker), isEmpty);
      expect(
        _spans(
          span,
        ).any((TextSpan child) => child.style?.fontWeight == FontWeight.bold),
        isTrue,
      );
    },
  );

  testWidgets(
    'source mode and composing range keep Markdown markers and IME offsets',
    (WidgetTester tester) async {
      final MessageEditorController controller = MessageEditorController(
        customEmojiBuilder: (_, _) => const SizedBox.shrink(),
        mode: MessageEditorMode.source,
      );
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: '`code`',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 1, end: 5),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );

      final TextEditingValue before = controller.value;
      final TextSpan span = controller.buildTextSpan(
        context: context,
        withComposing: true,
      );
      expect(span.toPlainText(), '`code`');
      expect(controller.value, before);
      expect(_spans(span).where(_isCollapsedMarker), isEmpty);
      expect(
        _spans(span).any(
          (TextSpan child) =>
              child.style?.decoration == TextDecoration.underline,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'inactive bullet and ordered list markers remain visible in live preview',
    (WidgetTester tester) async {
      final MessageEditorController controller = MessageEditorController(
        customEmojiBuilder: (_, _) => const SizedBox.shrink(),
      );
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: '- one\n12. two\nplain',
        selection: TextSelection.collapsed(offset: 19),
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );

      final TextSpan span = controller.buildTextSpan(
        context: context,
        withComposing: true,
      );
      final List<TextSpan> markers = _spans(span)
          .where(
            (TextSpan child) => (child.text == '- ' || child.text == '12. '),
          )
          .toList();

      expect(span.toPlainText(), controller.text);
      expect(markers, hasLength(2));
      expect(markers, isNot(contains(predicate(_isCollapsedMarker))));
    },
  );

  test(
    'toolbar commands update source selection and empty block backspace removes prefix',
    () {
      final MessageEditorController controller = MessageEditorController(
        customEmojiBuilder: (_, _) => const SizedBox.shrink(),
      );
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'bold',
        selection: TextSelection(baseOffset: 0, extentOffset: 4),
      );

      controller.applyFormattingCommand(MessageFormattingCommand.bold);
      expect(controller.text, '**bold**');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(
        controller.activeFormattingCommands,
        contains(MessageFormattingCommand.bold),
      );

      controller.value = const TextEditingValue(
        text: '- ',
        selection: TextSelection.collapsed(offset: 2),
      );
      controller.value = const TextEditingValue(
        text: '-',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(controller.text, isEmpty);
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    },
  );
}

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span case TextSpan(:final children)) {
    yield span;
    for (final InlineSpan? child in children ?? const <InlineSpan>[]) {
      if (child != null) yield* _spans(child);
    }
  }
}

bool _isCollapsedMarker(TextSpan span) => span.style?.fontSize == 0;

EmojiAutocompleteQuery? _query(String text) => findEmojiAutocompleteQuery(
  TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ),
);
