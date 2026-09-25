import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';

/// Parses the small Markdown subset that is safe to edit in the composer.
///
/// The parser is intentionally tolerant: it only reports source ranges and
/// diagnostics, never rewrites source. Offsets are UTF-16 offsets so inline
/// objects (`U+FFFC`) remain single, opaque editor characters.
class MarkdownEditingParser {
  const MarkdownEditingParser();

  MarkdownEditingDocument parse(String text) {
    final List<MarkdownToken> tokens = <MarkdownToken>[];
    final List<MarkdownEditingDiagnostic> diagnostics =
        <MarkdownEditingDiagnostic>[];
    final List<EditorRange> protectedRanges = <EditorRange>[];

    _parseFencedCode(text, tokens, diagnostics, protectedRanges);
    _parseInlineCode(text, tokens, diagnostics, protectedRanges);
    _parseBlocks(text, tokens, protectedRanges);
    _parseInlineFormatting(text, tokens, diagnostics, protectedRanges);

    tokens.sort((MarkdownToken a, MarkdownToken b) {
      final int start = a.rawRange.start.compareTo(b.rawRange.start);
      if (start != 0) return start;
      final int length = b.rawRange.length.compareTo(a.rawRange.length);
      if (length != 0) return length;
      return a.kind.index.compareTo(b.kind.index);
    });
    return MarkdownEditingDocument(
      text: text,
      tokens: tokens,
      diagnostics: diagnostics,
    );
  }

  void _parseFencedCode(
    String text,
    List<MarkdownToken> tokens,
    List<MarkdownEditingDiagnostic> diagnostics,
    List<EditorRange> protectedRanges,
  ) {
    final List<_Line> lines = _lines(text);
    var index = 0;
    while (index < lines.length) {
      final _Line line = lines[index];
      final _Fence? opening = _openingFenceAt(text, line);
      if (opening == null) {
        index += 1;
        continue;
      }
      var closingIndex = index + 1;
      while (closingIndex < lines.length &&
          _closingFenceAt(text, lines[closingIndex], opening) == null) {
        closingIndex += 1;
      }
      final EditorRange openingRange = EditorRange(
        start: line.start + opening.indentLength,
        end: line.contentEnd,
      );
      if (closingIndex == lines.length) {
        final EditorRange rawRange = EditorRange(
          start: line.start,
          end: text.length,
        );
        tokens.add(
          MarkdownToken(
            kind: MarkdownTokenKind.fencedCode,
            rawRange: rawRange,
            contentRange: EditorRange(start: line.end, end: text.length),
            openingMarkerRange: openingRange,
            closingMarkerRange: null,
          ),
        );
        diagnostics.add(
          MarkdownEditingDiagnostic(
            kind: MarkdownEditingDiagnosticKind.unclosedFence,
            range: openingRange,
          ),
        );
        protectedRanges.add(rawRange);
        break;
      }
      final _Line closingLine = lines[closingIndex];
      final _Fence closing = _closingFenceAt(text, closingLine, opening)!;
      final EditorRange rawRange = EditorRange(
        start: line.start,
        end: closingLine.contentEnd,
      );
      tokens.add(
        MarkdownToken(
          kind: MarkdownTokenKind.fencedCode,
          rawRange: rawRange,
          contentRange: EditorRange(start: line.end, end: closingLine.start),
          openingMarkerRange: openingRange,
          closingMarkerRange: EditorRange(
            start: closingLine.start + closing.indentLength,
            end: closingLine.contentEnd,
          ),
        ),
      );
      protectedRanges.add(rawRange);
      index = closingIndex + 1;
    }
  }

  void _parseInlineCode(
    String text,
    List<MarkdownToken> tokens,
    List<MarkdownEditingDiagnostic> diagnostics,
    List<EditorRange> protectedRanges,
  ) {
    var offset = 0;
    while (offset < text.length) {
      if (_isProtected(offset, protectedRanges) ||
          text.codeUnitAt(offset) != _backtick ||
          _isEscaped(text, offset)) {
        offset += 1;
        continue;
      }
      final int runLength = _runLength(text, offset, _backtick);
      final String marker = '`' * runLength;
      final int close = _findDelimiter(
        text,
        marker,
        offset + runLength,
        text.length,
        protectedRanges,
        preferLast: false,
      );
      final EditorRange opening = EditorRange(
        start: offset,
        end: offset + runLength,
      );
      if (close < 0) {
        final EditorRange rawRange = EditorRange(
          start: offset,
          end: text.length,
        );
        tokens.add(
          MarkdownToken(
            kind: MarkdownTokenKind.inlineCode,
            rawRange: rawRange,
            contentRange: EditorRange(start: opening.end, end: text.length),
            openingMarkerRange: opening,
            closingMarkerRange: null,
          ),
        );
        diagnostics.add(
          MarkdownEditingDiagnostic(
            kind: MarkdownEditingDiagnosticKind.unclosedInlineDelimiter,
            range: opening,
          ),
        );
        protectedRanges.add(rawRange);
        break;
      }
      final EditorRange rawRange = EditorRange(
        start: offset,
        end: close + runLength,
      );
      tokens.add(
        MarkdownToken(
          kind: MarkdownTokenKind.inlineCode,
          rawRange: rawRange,
          contentRange: EditorRange(start: opening.end, end: close),
          openingMarkerRange: opening,
          closingMarkerRange: EditorRange(start: close, end: close + runLength),
        ),
      );
      protectedRanges.add(rawRange);
      offset = close + runLength;
    }
  }

  void _parseBlocks(
    String text,
    List<MarkdownToken> tokens,
    List<EditorRange> protectedRanges,
  ) {
    for (final _Line line in _lines(text)) {
      if (_isProtected(line.start, protectedRanges)) continue;
      final String content = text.substring(line.start, line.contentEnd);
      final RegExpMatch? heading = RegExp(
        r'^( {0,3})(#{1,6}) ',
      ).firstMatch(content);
      if (heading != null) {
        final int markerEnd = line.start + heading.end;
        tokens.add(
          MarkdownToken(
            kind: MarkdownTokenKind.heading,
            rawRange: EditorRange(start: line.start, end: line.contentEnd),
            contentRange: EditorRange(start: markerEnd, end: line.contentEnd),
            openingMarkerRange: EditorRange(start: line.start, end: markerEnd),
            closingMarkerRange: EditorRange(
              start: line.contentEnd,
              end: line.contentEnd,
            ),
            level: heading.group(2)!.length,
          ),
        );
        continue;
      }
      final RegExpMatch? quote = RegExp(r'^( {0,3}> )').firstMatch(content);
      if (quote != null) {
        _addBlockToken(
          tokens,
          MarkdownTokenKind.quote,
          line,
          line.start + quote.end,
        );
        continue;
      }
      final RegExpMatch? unordered = RegExp(
        r'^( {0,3}[-+*] )',
      ).firstMatch(content);
      if (unordered != null) {
        _addBlockToken(
          tokens,
          MarkdownTokenKind.bulletedList,
          line,
          line.start + unordered.end,
        );
        continue;
      }
      final RegExpMatch? ordered = RegExp(
        r'^( {0,3})([0-9]+)\. ',
      ).firstMatch(content);
      if (ordered != null) {
        final int markerEnd = line.start + ordered.end;
        tokens.add(
          MarkdownToken(
            kind: MarkdownTokenKind.orderedList,
            rawRange: EditorRange(start: line.start, end: line.contentEnd),
            contentRange: EditorRange(start: markerEnd, end: line.contentEnd),
            openingMarkerRange: EditorRange(start: line.start, end: markerEnd),
            closingMarkerRange: EditorRange(
              start: line.contentEnd,
              end: line.contentEnd,
            ),
            orderedListNumber: int.parse(ordered.group(2)!),
          ),
        );
      }
    }
  }

  void _addBlockToken(
    List<MarkdownToken> tokens,
    MarkdownTokenKind kind,
    _Line line,
    int markerEnd,
  ) {
    tokens.add(
      MarkdownToken(
        kind: kind,
        rawRange: EditorRange(start: line.start, end: line.contentEnd),
        contentRange: EditorRange(start: markerEnd, end: line.contentEnd),
        openingMarkerRange: EditorRange(start: line.start, end: markerEnd),
        closingMarkerRange: EditorRange(
          start: line.contentEnd,
          end: line.contentEnd,
        ),
      ),
    );
  }

  void _parseInlineFormatting(
    String text,
    List<MarkdownToken> tokens,
    List<MarkdownEditingDiagnostic> diagnostics,
    List<EditorRange> protectedRanges,
  ) {
    _parseInlineSegment(
      text,
      0,
      text.length,
      tokens,
      diagnostics,
      protectedRanges,
    );
  }

  void _parseInlineSegment(
    String text,
    int start,
    int end,
    List<MarkdownToken> tokens,
    List<MarkdownEditingDiagnostic> diagnostics,
    List<EditorRange> protectedRanges,
  ) {
    var offset = start;
    while (offset < end) {
      if (_isProtected(offset, protectedRanges) || _isEscaped(text, offset)) {
        offset += 1;
        continue;
      }
      final _Delimiter? delimiter = _delimiterAt(text, offset, end);
      if (delimiter == null || !_canOpen(text, offset, delimiter.marker)) {
        offset += 1;
        continue;
      }
      final int close = _findFormattingCloser(
        text,
        delimiter.marker,
        offset + delimiter.marker.length,
        end,
        protectedRanges,
      );
      final EditorRange opening = EditorRange(
        start: offset,
        end: offset + delimiter.marker.length,
      );
      if (close < 0 || !_canClose(text, close, delimiter.marker)) {
        final EditorRange rawRange = EditorRange(start: offset, end: end);
        tokens.add(
          MarkdownToken(
            kind: delimiter.kind,
            rawRange: rawRange,
            contentRange: EditorRange(start: opening.end, end: end),
            openingMarkerRange: opening,
            closingMarkerRange: null,
          ),
        );
        diagnostics.add(
          MarkdownEditingDiagnostic(
            kind: MarkdownEditingDiagnosticKind.unclosedInlineDelimiter,
            range: opening,
          ),
        );
        return;
      }
      final EditorRange closing = EditorRange(
        start: close,
        end: close + delimiter.marker.length,
      );
      tokens.add(
        MarkdownToken(
          kind: delimiter.kind,
          rawRange: EditorRange(start: offset, end: closing.end),
          contentRange: EditorRange(start: opening.end, end: closing.start),
          openingMarkerRange: opening,
          closingMarkerRange: closing,
        ),
      );
      _parseInlineSegment(
        text,
        opening.end,
        closing.start,
        tokens,
        diagnostics,
        protectedRanges,
      );
      offset = closing.end;
    }
  }

  _Delimiter? _delimiterAt(String text, int offset, int end) {
    if (offset + 2 <= end && text.startsWith('**', offset)) {
      return const _Delimiter('**', MarkdownTokenKind.bold);
    }
    if (offset + 2 <= end && text.startsWith('__', offset)) {
      return const _Delimiter('__', MarkdownTokenKind.bold);
    }
    if (offset + 2 <= end && text.startsWith('~~', offset)) {
      return const _Delimiter('~~', MarkdownTokenKind.strike);
    }
    final int codeUnit = text.codeUnitAt(offset);
    if (codeUnit == _asterisk) {
      return const _Delimiter('*', MarkdownTokenKind.italic);
    }
    if (codeUnit == _underscore) {
      return const _Delimiter('_', MarkdownTokenKind.italic);
    }
    return null;
  }

  int _findDelimiter(
    String text,
    String marker,
    int start,
    int end,
    List<EditorRange> protectedRanges, {
    required bool preferLast,
  }) {
    var candidate = -1;
    var offset = start;
    while (offset + marker.length <= end) {
      if (text.startsWith(marker, offset) &&
          !_isProtected(offset, protectedRanges) &&
          !_isEscaped(text, offset)) {
        if (!preferLast) return offset;
        candidate = offset;
      }
      offset += 1;
    }
    return candidate;
  }

  int _findFormattingCloser(
    String text,
    String marker,
    int start,
    int end,
    List<EditorRange> protectedRanges,
  ) {
    var offset = start;
    while (offset + marker.length <= end) {
      final bool matches =
          text.startsWith(marker, offset) &&
          !_isProtected(offset, protectedRanges) &&
          !_isEscaped(text, offset) &&
          _canClose(text, offset, marker);
      if (matches) {
        // The final `***` in `***text***` closes the inner italic at its first
        // asterisk and the outer bold at its final two asterisks. For bold,
        // choose that latter two-character range; ordinary adjacent spans keep
        // their nearest closing delimiter.
        if (marker == '**' &&
            offset + marker.length < end &&
            text.codeUnitAt(offset + marker.length) == _asterisk &&
            text.startsWith(marker, offset + 1)) {
          return offset + 1;
        }
        return offset;
      }
      offset += 1;
    }
    return -1;
  }

  bool _canOpen(String text, int offset, String marker) {
    if (marker.startsWith('_') &&
        offset > 0 &&
        _isWord(text.codeUnitAt(offset - 1))) {
      return false;
    }
    final int next = offset + marker.length;
    return next < text.length && !_isWhitespace(text.codeUnitAt(next));
  }

  bool _canClose(String text, int offset, String marker) {
    if (marker.startsWith('_') &&
        offset + marker.length < text.length &&
        _isWord(text.codeUnitAt(offset + marker.length))) {
      return false;
    }
    return offset > 0 && !_isWhitespace(text.codeUnitAt(offset - 1));
  }

  bool _isProtected(int offset, List<EditorRange> ranges) =>
      ranges.any((EditorRange range) => range.contains(offset));

  bool _isEscaped(String text, int offset) {
    var slashCount = 0;
    var cursor = offset - 1;
    while (cursor >= 0 && text.codeUnitAt(cursor) == _backslash) {
      slashCount += 1;
      cursor -= 1;
    }
    return slashCount.isOdd;
  }

  int _runLength(String text, int offset, int codeUnit) {
    var length = 0;
    while (offset + length < text.length &&
        text.codeUnitAt(offset + length) == codeUnit) {
      length += 1;
    }
    return length;
  }

  List<_Line> _lines(String text) {
    final List<_Line> result = <_Line>[];
    var start = 0;
    while (start < text.length) {
      final int newline = text.indexOf('\n', start);
      final int end = newline < 0 ? text.length : newline + 1;
      final int contentEnd = newline < 0
          ? text.length
          : newline > start && text.codeUnitAt(newline - 1) == _carriageReturn
          ? newline - 1
          : newline;
      result.add(_Line(start: start, contentEnd: contentEnd, end: end));
      start = end;
    }
    if (text.isEmpty || text.endsWith('\n')) {
      result.add(
        _Line(start: text.length, contentEnd: text.length, end: text.length),
      );
    }
    return result;
  }

  _Fence? _openingFenceAt(String text, _Line line) {
    final String content = text.substring(line.start, line.contentEnd);
    final RegExpMatch? match = RegExp(
      r'^( {0,3})(`{3,})[^`]*$',
    ).firstMatch(content);
    if (match == null) return null;
    return _Fence(
      indentLength: match.group(1)!.length,
      markerLength: match.group(2)!.length,
    );
  }

  _Fence? _closingFenceAt(String text, _Line line, _Fence opening) {
    final String content = text.substring(line.start, line.contentEnd);
    final RegExpMatch? match = RegExp(
      r'^( {0,3})(`{3,})[ \t]*$',
    ).firstMatch(content);
    if (match == null || match.group(2)!.length < opening.markerLength) {
      return null;
    }
    return _Fence(
      indentLength: match.group(1)!.length,
      markerLength: match.group(2)!.length,
    );
  }
}

class _Line {
  const _Line({
    required this.start,
    required this.contentEnd,
    required this.end,
  });

  final int start;
  final int contentEnd;
  final int end;
}

class _Fence {
  const _Fence({required this.indentLength, required this.markerLength});

  final int indentLength;
  final int markerLength;
}

class _Delimiter {
  const _Delimiter(this.marker, this.kind);

  final String marker;
  final MarkdownTokenKind kind;
}

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

bool _isWord(int codeUnit) =>
    codeUnit >= 0x30 && codeUnit <= 0x39 ||
    codeUnit >= 0x41 && codeUnit <= 0x5A ||
    codeUnit >= 0x61 && codeUnit <= 0x7A ||
    codeUnit == _underscore ||
    codeUnit >= 0x80;

const int _asterisk = 0x2A;
const int _backslash = 0x5C;
const int _backtick = 0x60;
const int _carriageReturn = 0x0D;
const int _underscore = 0x5F;
