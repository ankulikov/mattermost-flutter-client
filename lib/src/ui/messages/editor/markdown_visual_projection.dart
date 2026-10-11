import 'package:flutter/material.dart';

import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/message_editor_mode.dart';

/// A styled source range in the editor's unchanged Markdown buffer.
///
/// [range] always refers to the raw UTF-16 editing buffer.  In particular,
/// hidden syntax remains part of the range and must be emitted as text by the
/// caller so `InlineSpan.toPlainText()` stays equal to the editing value.
class MarkdownVisualRun {
  const MarkdownVisualRun({
    required this.range,
    required this.style,
    required this.isHiddenMarker,
  });

  final EditorRange range;
  final TextStyle? style;
  final bool isHiddenMarker;
}

/// Projects a tolerant Markdown document onto the same editing buffer.
///
/// This class deliberately has no editing side effects.  It only returns
/// source ranges and styles, leaving the controller to preserve rich inline
/// objects as `WidgetSpan`s in their original positions.
class MarkdownVisualProjection {
  const MarkdownVisualProjection();

  List<MarkdownVisualRun> project({
    required MarkdownEditingDocument document,
    required TextSelection selection,
    required TextRange composing,
    required MessageEditorMode mode,
    required TextStyle baseStyle,
    required ColorScheme colors,
  }) {
    final String text = document.text;
    if (text.isEmpty) return const <MarkdownVisualRun>[];

    final Set<int> boundaries = <int>{0, text.length};
    for (final MarkdownToken token in document.tokens) {
      _addRangeBoundaries(boundaries, token.rawRange);
      _addRangeBoundaries(boundaries, token.contentRange);
      _addRangeBoundaries(boundaries, token.openingMarkerRange);
      final EditorRange? closing = token.closingMarkerRange;
      if (closing != null) _addRangeBoundaries(boundaries, closing);
    }
    if (composing.isValid && !composing.isCollapsed) {
      boundaries
        ..add(composing.start.clamp(0, text.length))
        ..add(composing.end.clamp(0, text.length));
    }
    final List<int> offsets = boundaries.toList()..sort();
    final List<MarkdownVisualRun> runs = <MarkdownVisualRun>[];
    for (var index = 0; index < offsets.length - 1; index += 1) {
      final EditorRange range = EditorRange(
        start: offsets[index],
        end: offsets[index + 1],
      );
      if (range.isCollapsed) continue;
      final List<MarkdownToken> covering = document.tokens
          .where((MarkdownToken token) => token.rawRange.intersects(range))
          .toList(growable: false);
      final List<MarkdownToken> contentTokens = covering
          .where((MarkdownToken token) => token.contentRange.intersects(range))
          .toList(growable: false);
      final bool hiddenMarker =
          mode == MessageEditorMode.livePreview &&
          covering.any(
            (MarkdownToken token) =>
                token.isComplete &&
                !_isActive(token, selection, composing) &&
                _isMarkerRange(token, range) &&
                !_isListPrefix(token, range),
          );
      TextStyle? style = mode == MessageEditorMode.livePreview
          ? _contentStyle(
              baseStyle: baseStyle,
              colors: colors,
              tokens: contentTokens,
            )
          : null;
      if (hiddenMarker) {
        // Keeping the source text in a zero-advance span preserves Flutter's
        // native offset model while visually collapsing inactive syntax.
        style = (style ?? baseStyle).copyWith(fontSize: 0, letterSpacing: 0);
      }
      if (_intersectsComposing(range, composing)) {
        style = (style ?? baseStyle).copyWith(
          decoration: TextDecoration.underline,
        );
      }
      runs.add(
        MarkdownVisualRun(
          range: range,
          style: style,
          isHiddenMarker: hiddenMarker,
        ),
      );
    }
    return runs;
  }

  void _addRangeBoundaries(Set<int> boundaries, EditorRange range) {
    boundaries
      ..add(range.start)
      ..add(range.end);
  }

  bool _isMarkerRange(MarkdownToken token, EditorRange range) {
    if (token.openingMarkerRange.intersects(range)) return true;
    final EditorRange? closing = token.closingMarkerRange;
    return closing != null && closing.intersects(range);
  }

  // A TextField cannot replace source syntax with a separate rendered bullet
  // without creating extra editing offsets. Keeping `- `, `* `, or `1. `
  // visible naturally indents the item content and preserves native editing.
  bool _isListPrefix(MarkdownToken token, EditorRange range) =>
      (token.kind == MarkdownTokenKind.bulletedList ||
          token.kind == MarkdownTokenKind.orderedList) &&
      token.openingMarkerRange.intersects(range);

  bool _isActive(
    MarkdownToken token,
    TextSelection selection,
    TextRange composing,
  ) {
    if (selection.isValid) {
      if (selection.isCollapsed) {
        if (token.rawRange.containsOrTouches(selection.extentOffset)) {
          return true;
        }
      } else if (token.rawRange.intersects(_selectionRange(selection))) {
        return true;
      }
    }
    return composing.isValid &&
        !composing.isCollapsed &&
        token.rawRange.intersects(
          EditorRange(start: composing.start, end: composing.end),
        );
  }

  EditorRange _selectionRange(TextSelection selection) =>
      EditorRange(start: selection.start, end: selection.end);

  bool _intersectsComposing(EditorRange range, TextRange composing) =>
      composing.isValid &&
      !composing.isCollapsed &&
      range.intersects(EditorRange(start: composing.start, end: composing.end));

  TextStyle? _contentStyle({
    required TextStyle baseStyle,
    required ColorScheme colors,
    required List<MarkdownToken> tokens,
  }) {
    if (tokens.isEmpty) return null;
    TextStyle style = baseStyle;
    var hasStyle = false;
    for (final MarkdownToken token in tokens) {
      switch (token.kind) {
        case MarkdownTokenKind.bold:
          style = style.copyWith(fontWeight: FontWeight.bold);
          hasStyle = true;
        case MarkdownTokenKind.italic:
          style = style.copyWith(fontStyle: FontStyle.italic);
          hasStyle = true;
        case MarkdownTokenKind.strike:
          style = style.copyWith(decoration: TextDecoration.lineThrough);
          hasStyle = true;
        case MarkdownTokenKind.link:
          style = style.copyWith(
            color: colors.primary,
            decoration: TextDecoration.underline,
            decorationColor: colors.primary,
          );
          hasStyle = true;
        case MarkdownTokenKind.inlineCode:
        case MarkdownTokenKind.fencedCode:
          style = style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: colors.surfaceContainerHighest,
          );
          hasStyle = true;
        case MarkdownTokenKind.heading:
          final int level = token.level ?? 3;
          final double baseSize = baseStyle.fontSize ?? 16;
          final double multiplier = switch (level) {
            1 => 1.8,
            2 => 1.55,
            3 => 1.35,
            4 => 1.2,
            5 => 1.1,
            _ => 1,
          };
          style = style.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: baseSize * multiplier,
          );
          hasStyle = true;
        case MarkdownTokenKind.quote:
          style = style.copyWith(color: colors.onSurfaceVariant);
          hasStyle = true;
        case MarkdownTokenKind.bulletedList:
        case MarkdownTokenKind.orderedList:
          hasStyle = true;
      }
    }
    return hasStyle ? style : null;
  }
}
