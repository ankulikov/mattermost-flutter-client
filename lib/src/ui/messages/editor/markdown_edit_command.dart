import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';

/// The unchanged source buffer and recalculated selection produced by a command.
class MarkdownEditCommandResult {
  const MarkdownEditCommandResult({
    required this.text,
    required this.selection,
  });

  final String text;
  final EditorSelection selection;
}

/// Pure source transformations used by the message formatting toolbar.
///
/// Commands preserve the source representation chosen by the user except for
/// the explicit prefix/delimiter being added or removed. They do not parse or
/// serialize inline objects; `U+FFFC` is simply one opaque UTF-16 code unit.
abstract final class MarkdownEditCommands {
  static MarkdownEditCommandResult bold(
    String text,
    EditorSelection selection,
  ) => _toggleInline(text, selection, marker: '**', kind: _InlineKind.bold);

  static MarkdownEditCommandResult italic(
    String text,
    EditorSelection selection,
  ) => _toggleInline(text, selection, marker: '*', kind: _InlineKind.italic);

  static MarkdownEditCommandResult strike(
    String text,
    EditorSelection selection,
  ) => _toggleInline(text, selection, marker: '~~', kind: _InlineKind.strike);

  static MarkdownEditCommandResult link(
    String text,
    EditorSelection selection,
  ) {
    _validateSelection(text, selection);
    if (selection.isCollapsed) {
      return MarkdownEditCommandResult(
        text: text.replaceRange(selection.start, selection.end, '[](url)'),
        selection: EditorSelection.collapsed(selection.start + 1),
      );
    }
    final _TrimmedSelection trimmed = _trimSelection(text, selection);
    if (trimmed.isEmpty) return link(text, trimmed.selection);
    final EditorSelection contentSelection = trimmed.selection;
    final int openingStart = contentSelection.start - 1;
    final int suffixStart = contentSelection.end;
    if (openingStart >= 0 &&
        text.codeUnitAt(openingStart) == _leftBracket &&
        text.startsWith('](', suffixStart)) {
      final int destinationEnd = _linkDestinationEnd(text, suffixStart + 2);
      if (destinationEnd >= 0) {
        final String result = text
            .replaceRange(suffixStart, destinationEnd + 1, '')
            .replaceRange(openingStart, contentSelection.start, '');
        return MarkdownEditCommandResult(
          text: result,
          selection: EditorSelection(
            baseOffset: contentSelection.baseOffset - 1,
            extentOffset: contentSelection.extentOffset - 1,
          ),
        );
      }
    }
    return _wrap(text, contentSelection, '[', '](url)');
  }

  static MarkdownEditCommandResult code(
    String text,
    EditorSelection selection,
  ) {
    _validateSelection(text, selection);
    if (selection.isCollapsed) {
      return MarkdownEditCommandResult(
        text: text.replaceRange(selection.start, selection.end, '``'),
        selection: EditorSelection.collapsed(selection.start + 1),
      );
    }
    final _TrimmedSelection trimmed = _trimSelection(text, selection);
    if (trimmed.isEmpty) return _replaceWithEmptyPair(text, selection, '``', 1);
    final EditorSelection contentSelection = trimmed.selection;
    const String opening = '`';
    const String closing = '`';
    if (_surroundedBy(text, contentSelection, opening, closing)) {
      return _removeSurrounding(
        text,
        contentSelection,
        opening.length,
        closing.length,
      );
    }
    const String fencedOpening = '```\n';
    const String fencedClosing = '\n```';
    if (_surroundedBy(text, contentSelection, fencedOpening, fencedClosing)) {
      return _removeSurrounding(
        text,
        contentSelection,
        fencedOpening.length,
        fencedClosing.length,
      );
    }
    if (text
        .substring(contentSelection.start, contentSelection.end)
        .contains('\n')) {
      return _wrap(text, contentSelection, fencedOpening, fencedClosing);
    }
    return _wrap(text, contentSelection, opening, closing);
  }

  static MarkdownEditCommandResult quote(
    String text,
    EditorSelection selection,
  ) => _toggleLinePrefix(text, selection, _LinePrefix.quote);

  static MarkdownEditCommandResult bulletedList(
    String text,
    EditorSelection selection,
  ) => _toggleLinePrefix(text, selection, _LinePrefix.bulletedList);

  static MarkdownEditCommandResult orderedList(
    String text,
    EditorSelection selection,
  ) => _toggleLinePrefix(text, selection, _LinePrefix.orderedList);

  static MarkdownEditCommandResult heading(
    String text,
    EditorSelection selection,
  ) => _toggleLinePrefix(text, selection, _LinePrefix.heading);

  // Explicit aliases keep call sites readable while matching toolbar labels.
  static MarkdownEditCommandResult toggleBold(
    String text,
    EditorSelection selection,
  ) => bold(text, selection);

  static MarkdownEditCommandResult toggleItalic(
    String text,
    EditorSelection selection,
  ) => italic(text, selection);

  static MarkdownEditCommandResult toggleStrike(
    String text,
    EditorSelection selection,
  ) => strike(text, selection);

  static MarkdownEditCommandResult toggleLink(
    String text,
    EditorSelection selection,
  ) => link(text, selection);

  static MarkdownEditCommandResult toggleCode(
    String text,
    EditorSelection selection,
  ) => code(text, selection);

  static MarkdownEditCommandResult toggleQuote(
    String text,
    EditorSelection selection,
  ) => quote(text, selection);

  static MarkdownEditCommandResult toggleBulletedList(
    String text,
    EditorSelection selection,
  ) => bulletedList(text, selection);

  static MarkdownEditCommandResult toggleOrderedList(
    String text,
    EditorSelection selection,
  ) => orderedList(text, selection);

  static MarkdownEditCommandResult toggleHeading(
    String text,
    EditorSelection selection,
  ) => heading(text, selection);

  static MarkdownEditCommandResult _toggleInline(
    String text,
    EditorSelection selection, {
    required String marker,
    required _InlineKind kind,
  }) {
    _validateSelection(text, selection);
    if (selection.isCollapsed) {
      return _replaceWithEmptyPair(
        text,
        selection,
        '$marker$marker',
        marker.length,
      );
    }
    final _TrimmedSelection trimmed = _trimSelection(text, selection);
    if (trimmed.isEmpty) {
      return _replaceWithEmptyPair(
        text,
        selection,
        '$marker$marker',
        marker.length,
      );
    }
    final EditorSelection contentSelection = trimmed.selection;
    if (kind == _InlineKind.italic &&
        _isStandaloneItalicLayer(text, contentSelection)) {
      return _removeSurrounding(text, contentSelection, 1, 1);
    }
    if (kind != _InlineKind.italic &&
        _surroundedBy(text, contentSelection, marker, marker)) {
      return _removeSurrounding(
        text,
        contentSelection,
        marker.length,
        marker.length,
      );
    }

    if (kind == _InlineKind.italic &&
        _surroundedBy(text, contentSelection, '***', '***')) {
      return _removeSurrounding(text, contentSelection, 1, 1);
    }

    // `***text***` consists of an outer bold layer and an inner italic layer.
    // Removing bold retains the direct italic delimiters around the selection.
    if (kind == _InlineKind.bold &&
        _surroundedBy(text, contentSelection, '***', '***')) {
      final int start = contentSelection.start;
      final int end = contentSelection.end;
      final String result = text
          .replaceRange(end + 1, end + 3, '')
          .replaceRange(start - 3, start - 1, '');
      return MarkdownEditCommandResult(
        text: result,
        selection: EditorSelection(
          baseOffset: _shiftForRemoval(selection.baseOffset, start - 3, 2),
          extentOffset: _shiftForRemoval(selection.extentOffset, start - 3, 2),
        ),
      );
    }
    return _wrap(text, contentSelection, marker, marker);
  }

  static MarkdownEditCommandResult _replaceWithEmptyPair(
    String text,
    EditorSelection selection,
    String replacement,
    int cursorOffset,
  ) => MarkdownEditCommandResult(
    text: text.replaceRange(selection.start, selection.end, replacement),
    selection: EditorSelection.collapsed(selection.start + cursorOffset),
  );

  static MarkdownEditCommandResult _wrap(
    String text,
    EditorSelection content,
    String opening,
    String closing,
  ) {
    final String result = text
        .replaceRange(content.end, content.end, closing)
        .replaceRange(content.start, content.start, opening);
    return MarkdownEditCommandResult(
      text: result,
      selection: EditorSelection(
        baseOffset: content.baseOffset + opening.length,
        extentOffset: content.extentOffset + opening.length,
      ),
    );
  }

  static MarkdownEditCommandResult _removeSurrounding(
    String text,
    EditorSelection content,
    int openingLength,
    int closingLength,
  ) {
    final int openingStart = content.start - openingLength;
    final int closingStart = content.end;
    final String result = text
        .replaceRange(closingStart, closingStart + closingLength, '')
        .replaceRange(openingStart, openingStart + openingLength, '');
    return MarkdownEditCommandResult(
      text: result,
      selection: EditorSelection(
        baseOffset: content.baseOffset - openingLength,
        extentOffset: content.extentOffset - openingLength,
      ),
    );
  }

  static bool _surroundedBy(
    String text,
    EditorSelection selection,
    String opening,
    String closing,
  ) =>
      selection.start >= opening.length &&
      selection.end + closing.length <= text.length &&
      text.substring(selection.start - opening.length, selection.start) ==
          opening &&
      text.substring(selection.end, selection.end + closing.length) == closing;

  static bool _isStandaloneItalicLayer(String text, EditorSelection selection) {
    if (!_surroundedBy(text, selection, '*', '*')) return false;
    final bool hasOpeningNeighbor =
        selection.start >= 2 &&
        text.codeUnitAt(selection.start - 2) == _asterisk;
    final bool hasClosingNeighbor =
        selection.end + 1 < text.length &&
        text.codeUnitAt(selection.end + 1) == _asterisk;
    return !hasOpeningNeighbor && !hasClosingNeighbor;
  }

  static int _linkDestinationEnd(String text, int start) {
    var depth = 1;
    for (var offset = start; offset < text.length; offset += 1) {
      final int codeUnit = text.codeUnitAt(offset);
      if (codeUnit == _lineFeed || codeUnit == _carriageReturn) return -1;
      if (codeUnit == _backslash) {
        offset += 1;
        continue;
      }
      if (codeUnit == _leftParenthesis) {
        depth += 1;
      } else if (codeUnit == _rightParenthesis) {
        depth -= 1;
        if (depth == 0) return offset;
      }
    }
    return -1;
  }

  static MarkdownEditCommandResult _toggleLinePrefix(
    String text,
    EditorSelection selection,
    _LinePrefix prefix,
  ) {
    _validateSelection(text, selection);
    final List<_CommandLine> lines = _affectedLines(text, selection);
    final bool remove = lines.every(
      (_CommandLine line) => prefix.match(line.text) != null,
    );
    final List<_TextEdit> edits = <_TextEdit>[];
    var ordinal = 1;
    for (final _CommandLine line in lines) {
      final RegExpMatch? match = prefix.match(line.text);
      if (remove) {
        edits.add(
          _TextEdit(
            start: line.start,
            end: line.start + match!.end,
            replacement: '',
          ),
        );
        continue;
      }
      if (match != null) {
        if (prefix == _LinePrefix.orderedList) ordinal += 1;
        continue;
      }
      final String insertion = prefix.insertion(ordinal);
      edits.add(
        _TextEdit(start: line.start, end: line.start, replacement: insertion),
      );
      if (prefix == _LinePrefix.orderedList) ordinal += 1;
    }
    return _applyEdits(text, selection, edits);
  }

  static MarkdownEditCommandResult _applyEdits(
    String text,
    EditorSelection selection,
    List<_TextEdit> edits,
  ) {
    String result = text;
    for (final _TextEdit edit in edits.reversed) {
      result = result.replaceRange(edit.start, edit.end, edit.replacement);
    }
    return MarkdownEditCommandResult(
      text: result,
      selection: EditorSelection(
        baseOffset: _mapEdits(selection.baseOffset, edits),
        extentOffset: _mapEdits(selection.extentOffset, edits),
      ),
    );
  }

  static int _mapEdits(int offset, List<_TextEdit> edits) {
    var mapped = offset;
    for (final _TextEdit edit in edits) {
      if (offset < edit.start) break;
      if (offset <= edit.end) {
        mapped = edit.start + edit.replacement.length;
      } else {
        mapped += edit.replacement.length - (edit.end - edit.start);
      }
    }
    return mapped;
  }

  static int _shiftForRemoval(int offset, int removalStart, int length) =>
      offset <= removalStart
      ? offset
      : offset < removalStart + length
      ? removalStart
      : offset - length;

  static _TrimmedSelection _trimSelection(
    String text,
    EditorSelection selection,
  ) {
    var start = selection.start;
    var end = selection.end;
    while (start < end && _isWhitespace(text.codeUnitAt(start))) {
      start += 1;
    }
    while (end > start && _isWhitespace(text.codeUnitAt(end - 1))) {
      end -= 1;
    }
    if (selection.isReversed) {
      return _TrimmedSelection(
        EditorSelection(baseOffset: end, extentOffset: start),
      );
    }
    return _TrimmedSelection(
      EditorSelection(baseOffset: start, extentOffset: end),
    );
  }

  static List<_CommandLine> _affectedLines(
    String text,
    EditorSelection selection,
  ) {
    final List<_CommandLine> lines = <_CommandLine>[];
    var lineStart = 0;
    var cursor = 0;
    final int inclusiveEnd = selection.isCollapsed
        ? selection.end
        : selection.end > selection.start &&
              selection.end <= text.length &&
              selection.end > 0 &&
              text.codeUnitAt(selection.end - 1) == _lineFeed
        ? selection.end - 1
        : selection.end;
    while (cursor <= text.length) {
      final int newline = text.indexOf('\n', cursor);
      final int contentEnd = newline < 0
          ? text.length
          : newline > lineStart &&
                text.codeUnitAt(newline - 1) == _carriageReturn
          ? newline - 1
          : newline;
      if (lineStart <= inclusiveEnd && contentEnd >= selection.start) {
        lines.add(
          _CommandLine(
            start: lineStart,
            text: text.substring(lineStart, contentEnd),
          ),
        );
      }
      if (newline < 0) break;
      cursor = newline + 1;
      lineStart = cursor;
      if (cursor > inclusiveEnd && !selection.isCollapsed) break;
    }
    if (lines.isEmpty) {
      lines.add(_CommandLine(start: text.length, text: ''));
    }
    return lines;
  }

  static void _validateSelection(String text, EditorSelection selection) {
    if (selection.start > text.length || selection.end > text.length) {
      throw RangeError.range(selection.end, 0, text.length, 'selection');
    }
  }
}

enum _InlineKind { bold, italic, strike }

enum _LinePrefix {
  quote,
  bulletedList,
  orderedList,
  heading;

  RegExpMatch? match(String text) => switch (this) {
    _LinePrefix.quote => RegExp(r'^( {0,3}> )').firstMatch(text),
    _LinePrefix.bulletedList => RegExp(r'^( {0,3}[-+*] )').firstMatch(text),
    _LinePrefix.orderedList => RegExp(r'^( {0,3}[0-9]+\. )').firstMatch(text),
    _LinePrefix.heading => RegExp(r'^( {0,3}### )').firstMatch(text),
  };

  String insertion(int ordinal) => switch (this) {
    _LinePrefix.quote => '> ',
    _LinePrefix.bulletedList => '- ',
    _LinePrefix.orderedList => '$ordinal. ',
    _LinePrefix.heading => '### ',
  };
}

class _TrimmedSelection {
  const _TrimmedSelection(this.selection);

  final EditorSelection selection;
  bool get isEmpty => selection.isCollapsed;
}

class _TextEdit {
  const _TextEdit({
    required this.start,
    required this.end,
    required this.replacement,
  });

  final int start;
  final int end;
  final String replacement;
}

class _CommandLine {
  const _CommandLine({required this.start, required this.text});

  final int start;
  final String text;
}

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

const int _carriageReturn = 0x0D;
const int _lineFeed = 0x0A;
const int _asterisk = 0x2A;
const int _backslash = 0x5C;
const int _leftBracket = 0x5B;
const int _leftParenthesis = 0x28;
const int _rightParenthesis = 0x29;
