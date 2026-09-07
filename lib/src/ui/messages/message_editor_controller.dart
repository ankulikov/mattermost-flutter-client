import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';

const String _objectReplacementCharacter = '\uFFFC';

typedef CustomEmojiSpanBuilder =
    Widget Function(BuildContext context, CustomEmojiReference emoji);

/// The active `:shortcode` query and the complete token range it will replace.
final class EmojiAutocompleteQuery {
  const EmojiAutocompleteQuery({required this.range, required this.term});

  final TextRange range;
  final String term;
}

/// Editing boundary for message-specific rich inline content.
///
/// The editable value uses one object-replacement character per custom emoji so
/// selection and deletion stay native. [messageText] serializes those objects
/// back to Mattermost shortcodes. Future Markdown highlighting can be added in
/// [buildTextSpan] without changing the composer or its submission contract.
final class MessageEditorController extends TextEditingController {
  MessageEditorController({required this.customEmojiBuilder});

  final CustomEmojiSpanBuilder customEmojiBuilder;
  Map<int, CustomEmojiReference> _customEmojiAt = <int, CustomEmojiReference>{};
  bool _applyingRichEdit = false;

  EmojiAutocompleteQuery? get emojiAutocompleteQuery =>
      findEmojiAutocompleteQuery(value);

  String get messageText =>
      messageTextForRange(TextRange(start: 0, end: text.length));

  String messageTextForRange(TextRange range) {
    assert(range.isValid && range.end <= text.length);
    if (_customEmojiAt.isEmpty) {
      return text.substring(range.start, range.end);
    }
    final StringBuffer result = StringBuffer();
    var offset = range.start;
    final List<int> positions = _customEmojiAt.keys.toList()..sort();
    for (final int position in positions) {
      if (position < range.start || position >= range.end) continue;
      if (position < offset || text[position] != _objectReplacementCharacter) {
        continue;
      }
      result
        ..write(text.substring(offset, position))
        ..write(':${_customEmojiAt[position]!.name}:');
      offset = position + 1;
    }
    result.write(text.substring(offset, range.end));
    return result.toString();
  }

  void replaceSelectionWithText(String replacement) {
    final TextSelection selection = value.selection;
    if (!selection.isValid) return;
    _replaceRange(
      TextRange(start: selection.start, end: selection.end),
      replacement,
    );
  }

  void replaceQueryWithUnicode(EmojiAutocompleteQuery query, String unicode) {
    _replaceRange(query.range, unicode);
  }

  void replaceQueryWithCustomEmoji(
    EmojiAutocompleteQuery query,
    CustomEmojiReference emoji,
  ) {
    _replaceRange(query.range, _objectReplacementCharacter, emoji: emoji);
  }

  void _replaceRange(
    TextRange range,
    String replacement, {
    CustomEmojiReference? emoji,
  }) {
    final TextEditingValue previous = value;
    final String nextText = previous.text.replaceRange(
      range.start,
      range.end,
      replacement,
    );
    final Map<int, CustomEmojiReference> nextEmoji = _remapCustomEmoji(
      previous.text,
      nextText,
    );
    if (emoji != null) nextEmoji[range.start] = emoji;
    _customEmojiAt = nextEmoji;
    _applyingRichEdit = true;
    try {
      super.value = previous.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(
          offset: range.start + replacement.length,
        ),
        composing: TextRange.empty,
      );
    } finally {
      _applyingRichEdit = false;
    }
  }

  @override
  set value(TextEditingValue newValue) {
    if (!_applyingRichEdit && newValue.text != value.text) {
      _customEmojiAt = _remapCustomEmoji(value.text, newValue.text);
    }
    super.value = newValue;
  }

  Map<int, CustomEmojiReference> _remapCustomEmoji(
    String previous,
    String next,
  ) {
    if (_customEmojiAt.isEmpty) return <int, CustomEmojiReference>{};
    var prefix = 0;
    final int shortestLength = previous.length < next.length
        ? previous.length
        : next.length;
    while (prefix < shortestLength &&
        previous.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix += 1;
    }

    var suffix = 0;
    while (suffix < shortestLength - prefix &&
        previous.codeUnitAt(previous.length - suffix - 1) ==
            next.codeUnitAt(next.length - suffix - 1)) {
      suffix += 1;
    }

    final int replacedEnd = previous.length - suffix;
    final int delta = next.length - previous.length;
    return <int, CustomEmojiReference>{
      for (final MapEntry<int, CustomEmojiReference> entry
          in _customEmojiAt.entries)
        if (entry.key < prefix)
          entry.key: entry.value
        else if (entry.key >= replacedEnd)
          entry.key + delta: entry.value,
    };
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_customEmojiAt.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final List<InlineSpan> children = <InlineSpan>[];
    var offset = 0;
    final List<int> positions = _customEmojiAt.keys.toList()..sort();
    for (final int position in positions) {
      if (position < offset ||
          position >= text.length ||
          text[position] != _objectReplacementCharacter) {
        continue;
      }
      _addTextSpans(
        children,
        text.substring(offset, position),
        absoluteStart: offset,
        withComposing: withComposing,
      );
      final CustomEmojiReference emoji = _customEmojiAt[position]!;
      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Semantics(
            label: ':${emoji.name}:',
            child: SizedBox.square(
              dimension: 22,
              child: customEmojiBuilder(context, emoji),
            ),
          ),
        ),
      );
      offset = position + 1;
    }
    _addTextSpans(
      children,
      text.substring(offset),
      absoluteStart: offset,
      withComposing: withComposing,
    );
    return TextSpan(style: style, children: children);
  }

  void _addTextSpans(
    List<InlineSpan> children,
    String segment, {
    required int absoluteStart,
    required bool withComposing,
  }) {
    if (segment.isEmpty) return;
    final TextRange composing = value.composing;
    if (!withComposing ||
        !composing.isValid ||
        composing.isCollapsed ||
        composing.end <= absoluteStart ||
        composing.start >= absoluteStart + segment.length) {
      children.add(TextSpan(text: segment));
      return;
    }

    final int localStart = (composing.start - absoluteStart).clamp(
      0,
      segment.length,
    );
    final int localEnd = (composing.end - absoluteStart).clamp(
      0,
      segment.length,
    );
    if (localStart > 0) {
      children.add(TextSpan(text: segment.substring(0, localStart)));
    }
    children.add(
      TextSpan(
        text: segment.substring(localStart, localEnd),
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
    );
    if (localEnd < segment.length) {
      children.add(TextSpan(text: segment.substring(localEnd)));
    }
  }
}

EmojiAutocompleteQuery? findEmojiAutocompleteQuery(TextEditingValue value) {
  final TextSelection selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  if (value.composing.isValid && !value.composing.isCollapsed) return null;

  final int caret = selection.extentOffset;
  if (caret < 3 || caret > value.text.length) return null;
  var colon = caret - 1;
  while (colon >= 0 && _isEmojiNameCodeUnit(value.text.codeUnitAt(colon))) {
    colon -= 1;
  }
  if (colon < 0 || value.text.codeUnitAt(colon) != 0x3A) return null;

  final String term = value.text.substring(colon + 1, caret);
  if (term.length < 2) return null;
  if (colon > 0) {
    final int previous = value.text.codeUnitAt(colon - 1);
    if (_isEmojiNameCodeUnit(previous) || previous == 0x3A) return null;
  }

  var replaceEnd = caret;
  while (replaceEnd < value.text.length &&
      _isEmojiNameCodeUnit(value.text.codeUnitAt(replaceEnd))) {
    replaceEnd += 1;
  }
  if (replaceEnd < value.text.length &&
      value.text.codeUnitAt(replaceEnd) == 0x3A) {
    replaceEnd += 1;
  }
  return EmojiAutocompleteQuery(
    range: TextRange(start: colon, end: replaceEnd),
    term: term,
  );
}

bool _isEmojiNameCodeUnit(int value) =>
    value >= 0x41 && value <= 0x5A ||
    value >= 0x61 && value <= 0x7A ||
    value >= 0x30 && value <= 0x39 ||
    value == 0x5F ||
    value == 0x2D ||
    value == 0x2B;
