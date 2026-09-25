import 'dart:math' as math;

/// An immutable, half-open range in the editor's UTF-16 editing buffer.
///
/// Its offsets deliberately have the same coordinate system as Flutter's
/// `TextSelection`, while keeping the editing engine independent of Flutter.
class EditorRange {
  const EditorRange({required this.start, required this.end})
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;

  bool contains(int offset) => offset >= start && offset < end;

  bool containsOrTouches(int offset) => offset >= start && offset <= end;

  bool intersects(EditorRange other) => start < other.end && other.start < end;

  bool containsRange(EditorRange other) =>
      start <= other.start && other.end <= end;

  EditorRange shift(int delta) =>
      EditorRange(start: start + delta, end: end + delta);

  @override
  bool operator ==(Object other) =>
      other is EditorRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'EditorRange($start, $end)';
}

/// A directional selection in the editor's UTF-16 editing buffer.
class EditorSelection {
  const EditorSelection({required this.baseOffset, required this.extentOffset})
    : assert(baseOffset >= 0),
      assert(extentOffset >= 0);

  const EditorSelection.collapsed(int offset)
    : baseOffset = offset,
      extentOffset = offset,
      assert(offset >= 0);

  final int baseOffset;
  final int extentOffset;

  int get start => math.min(baseOffset, extentOffset);
  int get end => math.max(baseOffset, extentOffset);
  int get length => end - start;
  bool get isCollapsed => baseOffset == extentOffset;
  bool get isReversed => baseOffset > extentOffset;
  EditorRange get range => EditorRange(start: start, end: end);

  EditorSelection copyWith({int? baseOffset, int? extentOffset}) =>
      EditorSelection(
        baseOffset: baseOffset ?? this.baseOffset,
        extentOffset: extentOffset ?? this.extentOffset,
      );

  @override
  bool operator ==(Object other) =>
      other is EditorSelection &&
      other.baseOffset == baseOffset &&
      other.extentOffset == extentOffset;

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);

  @override
  String toString() => 'EditorSelection($baseOffset, $extentOffset)';
}

/// The Markdown construct recognized at a source range.
enum MarkdownTokenKind {
  bold,
  italic,
  strike,
  inlineCode,
  fencedCode,
  heading,
  quote,
  bulletedList,
  orderedList,
}

/// A source-backed Markdown construct recognized by [MarkdownEditingParser].
///
/// Unclosed inline delimiters are represented by a token without a closing
/// marker. This lets the projection style typed content without modifying or
/// hiding the marker the user is still editing.
class MarkdownToken {
  const MarkdownToken({
    required this.kind,
    required this.rawRange,
    required this.contentRange,
    required this.openingMarkerRange,
    required this.closingMarkerRange,
    this.level,
    this.orderedListNumber,
  });

  final MarkdownTokenKind kind;
  final EditorRange rawRange;
  final EditorRange contentRange;
  final EditorRange openingMarkerRange;
  final EditorRange? closingMarkerRange;

  /// Heading level (one through six), when [kind] is heading.
  final int? level;

  /// The literal list number, when [kind] is orderedList.
  final int? orderedListNumber;

  bool get isComplete => closingMarkerRange != null;

  @override
  bool operator ==(Object other) =>
      other is MarkdownToken &&
      other.kind == kind &&
      other.rawRange == rawRange &&
      other.contentRange == contentRange &&
      other.openingMarkerRange == openingMarkerRange &&
      other.closingMarkerRange == closingMarkerRange &&
      other.level == level &&
      other.orderedListNumber == orderedListNumber;

  @override
  int get hashCode => Object.hash(
    kind,
    rawRange,
    contentRange,
    openingMarkerRange,
    closingMarkerRange,
    level,
    orderedListNumber,
  );
}

/// A non-destructive issue found while parsing incomplete Markdown.
enum MarkdownEditingDiagnosticKind { unclosedInlineDelimiter, unclosedFence }

class MarkdownEditingDiagnostic {
  const MarkdownEditingDiagnostic({required this.kind, required this.range});

  final MarkdownEditingDiagnosticKind kind;
  final EditorRange range;

  @override
  bool operator ==(Object other) =>
      other is MarkdownEditingDiagnostic &&
      other.kind == kind &&
      other.range == range;

  @override
  int get hashCode => Object.hash(kind, range);
}

/// An immutable, tolerant parse of the editor's unchanged source buffer.
class MarkdownEditingDocument {
  MarkdownEditingDocument({
    required this.text,
    required Iterable<MarkdownToken> tokens,
    required Iterable<MarkdownEditingDiagnostic> diagnostics,
  }) : tokens = List<MarkdownToken>.unmodifiable(tokens),
       diagnostics = List<MarkdownEditingDiagnostic>.unmodifiable(diagnostics);

  final String text;
  final List<MarkdownToken> tokens;
  final List<MarkdownEditingDiagnostic> diagnostics;

  Iterable<MarkdownToken> tokensOf(MarkdownTokenKind kind) =>
      tokens.where((MarkdownToken token) => token.kind == kind);
}
