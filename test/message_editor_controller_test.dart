import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/ui/messages/message_editor_controller.dart';

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
}

EmojiAutocompleteQuery? _query(String text) => findEmojiAutocompleteQuery(
  TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  ),
);
