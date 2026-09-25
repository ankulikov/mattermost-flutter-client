import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/models/user_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_edit_command.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_parser.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_visual_projection.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/message_editor_mode.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/message_formatting_toolbar.dart';

const String _objectReplacementCharacter = '\uFFFC';

typedef CustomEmojiSpanBuilder =
    Widget Function(BuildContext context, CustomEmojiReference emoji);

typedef UserMentionSpanBuilder =
    Widget Function(BuildContext context, UserMention mention);

typedef GroupMentionSpanBuilder =
    Widget Function(BuildContext context, GroupMention mention);

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

final class GroupMentionInlineObject extends MessageInlineObject {
  const GroupMentionInlineObject(this.mention);

  final GroupMention mention;

  @override
  String get wireText => '@${mention.name}';
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
    GroupMentionSpanBuilder? groupMentionBuilder,
    MessageEditorMode mode = MessageEditorMode.livePreview,
  }) : userMentionBuilder = userMentionBuilder ?? _defaultUserMentionBuilder,
       groupMentionBuilder = groupMentionBuilder ?? _defaultGroupMentionBuilder,
       _mode = mode;

  final CustomEmojiSpanBuilder customEmojiBuilder;
  final UserMentionSpanBuilder userMentionBuilder;
  final GroupMentionSpanBuilder groupMentionBuilder;
  final MarkdownEditingParser _parser = const MarkdownEditingParser();
  final MarkdownVisualProjection _projection = const MarkdownVisualProjection();
  Map<int, MessageInlineObject> _inlineObjectAt = <int, MessageInlineObject>{};
  final Set<int> _autoMentionSeparatorAt = <int>{};
  bool _applyingRichEdit = false;
  MessageEditorMode _mode;

  MessageEditorMode get mode => _mode;

  set mode(MessageEditorMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
  }

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

  /// Applies a toolbar command to the raw Markdown source and preserves its
  /// recalculated UTF-16 selection. Inline objects are remapped by [value]'s
  /// existing edit boundary rather than serialized into the editing buffer.
  void applyFormattingCommand(MessageFormattingCommand command) {
    final EditorSelection selection = _editorSelection;
    final MarkdownEditCommandResult result = switch (command) {
      MessageFormattingCommand.bold => MarkdownEditCommands.bold(
        text,
        selection,
      ),
      MessageFormattingCommand.italic => MarkdownEditCommands.italic(
        text,
        selection,
      ),
      MessageFormattingCommand.strike => MarkdownEditCommands.strike(
        text,
        selection,
      ),
      MessageFormattingCommand.heading => MarkdownEditCommands.heading(
        text,
        selection,
      ),
      MessageFormattingCommand.code => MarkdownEditCommands.code(
        text,
        selection,
      ),
      MessageFormattingCommand.quote => MarkdownEditCommands.quote(
        text,
        selection,
      ),
      MessageFormattingCommand.bulletedList =>
        MarkdownEditCommands.bulletedList(text, selection),
      MessageFormattingCommand.orderedList => MarkdownEditCommands.orderedList(
        text,
        selection,
      ),
    };
    value = value.copyWith(
      text: result.text,
      selection: TextSelection(
        baseOffset: result.selection.baseOffset,
        extentOffset: result.selection.extentOffset,
      ),
      composing: TextRange.empty,
    );
  }

  /// Formatting controls highlighted for the current selection/document.
  Set<MessageFormattingCommand> get activeFormattingCommands {
    final MarkdownEditingDocument document = _parser.parse(text);
    return MessageFormattingCommand.values
        .where(
          (MessageFormattingCommand command) =>
              _isFormattingCommandActive(command, document),
        )
        .toSet();
  }

  EditorSelection get _editorSelection {
    final TextSelection selection = value.selection;
    if (!selection.isValid ||
        selection.start < 0 ||
        selection.end > text.length) {
      return EditorSelection.collapsed(text.length);
    }
    return EditorSelection(
      baseOffset: selection.baseOffset,
      extentOffset: selection.extentOffset,
    );
  }

  bool _isFormattingCommandActive(
    MessageFormattingCommand command,
    MarkdownEditingDocument document,
  ) {
    final TextSelection selection = value.selection;
    if (!selection.isValid) return false;
    final EditorRange selected = EditorRange(
      start: selection.start,
      end: selection.end,
    );
    final Set<MarkdownTokenKind> kinds = switch (command) {
      MessageFormattingCommand.bold => <MarkdownTokenKind>{
        MarkdownTokenKind.bold,
      },
      MessageFormattingCommand.italic => <MarkdownTokenKind>{
        MarkdownTokenKind.italic,
      },
      MessageFormattingCommand.strike => <MarkdownTokenKind>{
        MarkdownTokenKind.strike,
      },
      MessageFormattingCommand.heading => <MarkdownTokenKind>{
        MarkdownTokenKind.heading,
      },
      MessageFormattingCommand.code => <MarkdownTokenKind>{
        MarkdownTokenKind.inlineCode,
        MarkdownTokenKind.fencedCode,
      },
      MessageFormattingCommand.quote => <MarkdownTokenKind>{
        MarkdownTokenKind.quote,
      },
      MessageFormattingCommand.bulletedList => <MarkdownTokenKind>{
        MarkdownTokenKind.bulletedList,
      },
      MessageFormattingCommand.orderedList => <MarkdownTokenKind>{
        MarkdownTokenKind.orderedList,
      },
    };
    return document.tokens.any((MarkdownToken token) {
      if (!kinds.contains(token.kind)) return false;
      if (selection.isCollapsed) {
        return token.rawRange.containsOrTouches(selection.extentOffset);
      }
      return token.rawRange.intersects(selected);
    });
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
    _replaceQueryWithMentionObject(query, UserMentionInlineObject(mention));
  }

  /// Inserts a group mention without replacing its handle with a display name.
  void replaceQueryWithGroupMention(MentionQuery query, GroupMention mention) {
    _replaceQueryWithMentionObject(query, GroupMentionInlineObject(mention));
  }

  void _replaceQueryWithMentionObject(
    MentionQuery query,
    MessageInlineObject object,
  ) {
    final TextRange range = TextRange(start: query.start, end: query.end);
    final bool appendSeparator = range.end == text.length;
    _replaceRange(
      range,
      _objectReplacementCharacter,
      object: object,
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
      newValue = _removeEmptyBlockPrefixAfterBackspace(value, newValue);
    }
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
            (entry.value is UserMentionInlineObject ||
                entry.value is GroupMentionInlineObject) &&
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

  TextEditingValue _removeEmptyBlockPrefixAfterBackspace(
    TextEditingValue previous,
    TextEditingValue next,
  ) {
    final TextSelection oldSelection = previous.selection;
    final TextSelection newSelection = next.selection;
    if (!oldSelection.isValid ||
        !oldSelection.isCollapsed ||
        !newSelection.isValid ||
        !newSelection.isCollapsed ||
        oldSelection.start == 0 ||
        next.text.length != previous.text.length - 1) {
      return next;
    }
    final int oldCaret = oldSelection.start;
    final int lineStart = previous.text.lastIndexOf('\n', oldCaret - 1) + 1;
    final int lineEnd = previous.text.indexOf('\n', oldCaret);
    final int boundedLineEnd = lineEnd < 0 ? previous.text.length : lineEnd;
    if (boundedLineEnd != oldCaret) return next;
    final String prefix = previous.text.substring(lineStart, oldCaret);
    if (!RegExp(
      r'^(?: {0,3}(?:[-+*]|>|#{1,6}) | {0,3}[0-9]+\. )$',
    ).hasMatch(prefix)) {
      return next;
    }
    final int remainingPrefixLength = prefix.length - 1;
    if (remainingPrefixLength <= 0 ||
        next.text.substring(lineStart, lineStart + remainingPrefixLength) !=
            prefix.substring(0, remainingPrefixLength)) {
      return next;
    }
    return next.copyWith(
      text: next.text.replaceRange(
        lineStart,
        lineStart + remainingPrefixLength,
        '',
      ),
      selection: TextSelection.collapsed(offset: lineStart),
      composing: TextRange.empty,
    );
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
    final List<InlineSpan> children = <InlineSpan>[];
    final TextStyle baseStyle = style ?? DefaultTextStyle.of(context).style;
    final List<MarkdownVisualRun> runs = _projection.project(
      document: _parser.parse(text),
      selection: value.selection,
      composing: withComposing ? value.composing : TextRange.empty,
      mode: _mode,
      baseStyle: baseStyle,
      colors: Theme.of(context).colorScheme,
    );
    final List<int> positions = _inlineObjectAt.keys.toList()..sort();
    for (final MarkdownVisualRun run in runs) {
      _addProjectedRun(children, run, positions, context);
    }
    return TextSpan(style: style, children: children);
  }

  void _addProjectedRun(
    List<InlineSpan> children,
    MarkdownVisualRun run,
    List<int> objectPositions,
    BuildContext context,
  ) {
    var offset = run.range.start;
    for (final int position in objectPositions) {
      if (position < offset || position >= run.range.end) continue;
      if (position > offset) {
        children.add(
          TextSpan(text: text.substring(offset, position), style: run.style),
        );
      }
      final MessageInlineObject? object = _inlineObjectAt[position];
      if (object == null || text[position] != _objectReplacementCharacter) {
        children.add(TextSpan(text: text[position], style: run.style));
      } else {
        children.add(_inlineObjectSpan(context, object));
      }
      offset = position + 1;
    }
    if (offset < run.range.end) {
      children.add(
        TextSpan(text: text.substring(offset, run.range.end), style: run.style),
      );
    }
  }

  WidgetSpan _inlineObjectSpan(
    BuildContext context,
    MessageInlineObject object,
  ) => switch (object) {
    CustomEmojiInlineObject(:final CustomEmojiReference emoji) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        label: ':${emoji.name}:',
        child: SizedBox.square(
          dimension: 22,
          child: customEmojiBuilder(context, emoji),
        ),
      ),
    ),
    UserMentionInlineObject(:final UserMention mention) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Semantics(
        link: true,
        label: '@${mention.username}',
        child: userMentionBuilder(context, mention),
      ),
    ),
    GroupMentionInlineObject(:final GroupMention mention) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Semantics(
        link: true,
        label: '@${mention.name}',
        child: groupMentionBuilder(context, mention),
      ),
    ),
  };
}

Widget _defaultUserMentionBuilder(BuildContext context, UserMention mention) =>
    Text('@${mention.displayName}');

Widget _defaultGroupMentionBuilder(
  BuildContext context,
  GroupMention mention,
) => Text('@${mention.name}');

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
