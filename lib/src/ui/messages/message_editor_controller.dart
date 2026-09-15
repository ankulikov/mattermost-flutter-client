import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';

const String _objectReplacementCharacter = '\uFFFC';

typedef CustomEmojiSpanBuilder =
    Widget Function(BuildContext context, CustomEmojiReference emoji);

typedef UserMentionSpanBuilder =
    Widget Function(BuildContext context, UserMention mention);

/// Rich content represented by a single object-replacement character in the
/// editable value. Keeping the wire representation out of the editing value
/// makes a mention behave as one native editing unit.
sealed class MessageInlineObject {
  const MessageInlineObject();

  String get wireText;
}

final class CustomEmojiInlineObject extends MessageInlineObject {
  const CustomEmojiInlineObject(this.emoji);

  final CustomEmojiReference emoji;

  @override
  String get wireText => ':${emoji.name}:';
}

final class UserMentionInlineObject extends MessageInlineObject {
  const UserMentionInlineObject(this.mention);

  final UserMention mention;

  @override
  String get wireText => '@${mention.username}';
}

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
  MessageEditorController({
    required this.customEmojiBuilder,
    UserMentionSpanBuilder? userMentionBuilder,
  }) : userMentionBuilder = userMentionBuilder ?? _defaultUserMentionBuilder;

  final CustomEmojiSpanBuilder customEmojiBuilder;
  final UserMentionSpanBuilder userMentionBuilder;
  Map<int, MessageInlineObject> _inlineObjectAt = <int, MessageInlineObject>{};
  final Set<int> _autoMentionSeparatorAt = <int>{};
  bool _applyingRichEdit = false;

  EmojiAutocompleteQuery? get emojiAutocompleteQuery =>
      findEmojiAutocompleteQuery(value);

  String get messageText =>
      messageTextForRange(TextRange(start: 0, end: text.length));

  String messageTextForRange(TextRange range) {
    assert(range.isValid && range.end <= text.length);
    if (_inlineObjectAt.isEmpty) {
      return text.substring(range.start, range.end);
    }
    final StringBuffer result = StringBuffer();
    var offset = range.start;
    final List<int> positions = _inlineObjectAt.keys.toList()..sort();
    for (final int position in positions) {
      if (position < range.start || position >= range.end) continue;
      if (position < offset || text[position] != _objectReplacementCharacter) {
        continue;
      }
      result
        ..write(text.substring(offset, position))
        ..write(_inlineObjectAt[position]!.wireText);
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
    _replaceRange(
      query.range,
      _objectReplacementCharacter,
      object: CustomEmojiInlineObject(emoji),
    );
  }

  /// Replaces the complete active mention token with a single atomic object.
  /// A space is inserted only when the token ends at the text boundary, so a
  /// newly selected mention can be continued naturally without altering an
  /// existing punctuation or whitespace token.
  void replaceQueryWithMention(MentionQuery query, UserMention mention) {
    final TextRange range = TextRange(start: query.start, end: query.end);
    final bool appendSeparator = range.end == text.length;
    _replaceRange(
      range,
      _objectReplacementCharacter,
      object: UserMentionInlineObject(mention),
      appendMentionSeparator: appendSeparator,
    );
  }

  void _replaceRange(
    TextRange range,
    String replacement, {
    MessageInlineObject? object,
    bool appendMentionSeparator = false,
  }) {
    final TextEditingValue previous = value;
    final String inserted = appendMentionSeparator
        ? '$replacement '
        : replacement;
    final String nextText = previous.text.replaceRange(
      range.start,
      range.end,
      inserted,
    );
    final Map<int, MessageInlineObject> nextObjects = _remapInlineObjects(
      previous.text,
      nextText,
    );
    final Set<int> nextSeparators = _remapAutoMentionSeparators(
      previous.text,
      nextText,
    );
    if (object != null) nextObjects[range.start] = object;
    if (appendMentionSeparator) nextSeparators.add(range.start + 1);
    _inlineObjectAt = nextObjects;
    _autoMentionSeparatorAt
      ..clear()
      ..addAll(nextSeparators);
    _applyingRichEdit = true;
    try {
      super.value = previous.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(
          offset: range.start + inserted.length,
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
      final TextEditingValue previous = value;
      final _ExternalEdit edit = _ExternalEdit.from(
        previous.text,
        newValue.text,
      );
      final Map<int, MessageInlineObject> previousObjects =
          Map<int, MessageInlineObject>.of(_inlineObjectAt);
      final Set<int> previousSeparators = Set<int>.of(_autoMentionSeparatorAt);
      final Map<int, MessageInlineObject> nextObjects = _remapInlineObjects(
        previous.text,
        newValue.text,
      );
      final Set<int> nextSeparators = _remapAutoMentionSeparators(
        previous.text,
        newValue.text,
      );
      _inlineObjectAt = nextObjects;
      _autoMentionSeparatorAt
        ..clear()
        ..addAll(nextSeparators);

      // Backspace over an inserted mention should not leave behind its private
      // separator. This is intentionally limited to a separator that we added.
      final bool deletedMention = previousObjects.entries.any(
        (MapEntry<int, MessageInlineObject> entry) =>
            entry.value is UserMentionInlineObject &&
            entry.key >= edit.prefix &&
            entry.key < edit.replacedEnd,
      );
      if (deletedMention) {
        final int? separator = edit.firstDeletedAutoSeparator(
          previousSeparators,
          newValue.text,
        );
        if (separator != null) {
          final String interimText = newValue.text;
          newValue = newValue.copyWith(
            text: newValue.text.replaceRange(separator, separator + 1, ''),
            selection: _shiftSelectionAfterRemoval(
              newValue.selection,
              separator,
            ),
            composing: TextRange.empty,
          );
          final Map<int, MessageInlineObject> normalizedObjects =
              _remapInlineObjects(interimText, newValue.text);
          final Set<int> normalizedSeparators = _remapAutoMentionSeparators(
            interimText,
            newValue.text,
          );
          _inlineObjectAt = normalizedObjects;
          _autoMentionSeparatorAt
            ..clear()
            ..addAll(normalizedSeparators);
        }
      }
    }
    if (_composingIncludesInlineObject(newValue.composing)) {
      newValue = newValue.copyWith(composing: TextRange.empty);
    }
    super.value = newValue;
  }

  Map<int, MessageInlineObject> _remapInlineObjects(
    String previous,
    String next,
  ) {
    if (_inlineObjectAt.isEmpty) return <int, MessageInlineObject>{};
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
    return <int, MessageInlineObject>{
      for (final MapEntry<int, MessageInlineObject> entry
          in _inlineObjectAt.entries)
        if (entry.key < prefix)
          entry.key: entry.value
        else if (entry.key >= replacedEnd)
          entry.key + delta: entry.value,
    };
  }

  Set<int> _remapAutoMentionSeparators(String previous, String next) {
    if (_autoMentionSeparatorAt.isEmpty) return <int>{};
    final _ExternalEdit edit = _ExternalEdit.from(previous, next);
    return <int>{
      for (final int separator in _autoMentionSeparatorAt)
        if (separator < edit.prefix)
          separator
        else if (separator >= edit.replacedEnd)
          separator + edit.delta,
    };
  }

  bool _composingIncludesInlineObject(TextRange composing) =>
      composing.isValid &&
      !composing.isCollapsed &&
      _inlineObjectAt.keys.any(
        (int position) =>
            position >= composing.start && position < composing.end,
      );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_inlineObjectAt.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final List<InlineSpan> children = <InlineSpan>[];
    var offset = 0;
    final List<int> positions = _inlineObjectAt.keys.toList()..sort();
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
      final MessageInlineObject object = _inlineObjectAt[position]!;
      switch (object) {
        case CustomEmojiInlineObject(:final CustomEmojiReference emoji):
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
        case UserMentionInlineObject(:final UserMention mention):
          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Semantics(
                link: true,
                label: '@${mention.username}',
                child: userMentionBuilder(context, mention),
              ),
            ),
          );
      }
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

Widget _defaultUserMentionBuilder(BuildContext context, UserMention mention) =>
    Text('@${mention.displayName}');

TextSelection _shiftSelectionAfterRemoval(
  TextSelection selection,
  int offset,
) => selection.copyWith(
  baseOffset: selection.baseOffset > offset
      ? selection.baseOffset - 1
      : selection.baseOffset,
  extentOffset: selection.extentOffset > offset
      ? selection.extentOffset - 1
      : selection.extentOffset,
);

final class _ExternalEdit {
  const _ExternalEdit({
    required this.prefix,
    required this.replacedEnd,
    required this.delta,
  });

  factory _ExternalEdit.from(String previous, String next) {
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
    return _ExternalEdit(
      prefix: prefix,
      replacedEnd: previous.length - suffix,
      delta: next.length - previous.length,
    );
  }

  final int prefix;
  final int replacedEnd;
  final int delta;

  int? firstDeletedAutoSeparator(Set<int> separators, String nextText) {
    for (final int separator in separators) {
      if (separator >= replacedEnd) {
        final int remapped = separator + delta;
        if (remapped >= 0 &&
            remapped < nextText.length &&
            nextText[remapped] == ' ') {
          return remapped;
        }
      }
    }
    return null;
  }
}

EmojiAutocompleteQuery? findEmojiAutocompleteQuery(TextEditingValue value) {
  final TextSelection selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;

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
