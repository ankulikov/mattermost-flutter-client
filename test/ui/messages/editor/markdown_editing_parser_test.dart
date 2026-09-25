import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_parser.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/message_editor_mode.dart';

void main() {
  const MarkdownEditingParser parser = MarkdownEditingParser();

  group('MessageEditorMode', () {
    test('exposes live preview and source modes', () {
      expect(MessageEditorMode.values, <MessageEditorMode>[
        MessageEditorMode.livePreview,
        MessageEditorMode.source,
      ]);
    });
  });

  group('MarkdownEditingParser inline formatting', () {
    test('reports exact source ranges for bold', () {
      final MarkdownEditingDocument document = parser.parse('Hi **bold**!');
      final MarkdownToken token = _only(document, MarkdownTokenKind.bold);

      expect(token.rawRange, const EditorRange(start: 3, end: 11));
      expect(token.openingMarkerRange, const EditorRange(start: 3, end: 5));
      expect(token.contentRange, const EditorRange(start: 5, end: 9));
      expect(token.closingMarkerRange, const EditorRange(start: 9, end: 11));
      expect(token.isComplete, isTrue);
      expect(document.diagnostics, isEmpty);
    });

    test('parses nested triple asterisks as bold and italic', () {
      final MarkdownEditingDocument document = parser.parse('***text***');

      expect(document.tokensOf(MarkdownTokenKind.bold), hasLength(1));
      expect(document.tokensOf(MarkdownTokenKind.italic), hasLength(1));
      expect(
        _only(document, MarkdownTokenKind.bold).contentRange,
        const EditorRange(start: 2, end: 8),
      );
      expect(
        _only(document, MarkdownTokenKind.italic).contentRange,
        const EditorRange(start: 3, end: 7),
      );
    });

    test('supports bold, italic and strike nesting', () {
      final MarkdownEditingDocument document = parser.parse(
        '**bold *italic* and ~~strike~~**',
      );

      expect(document.tokensOf(MarkdownTokenKind.bold), hasLength(1));
      expect(document.tokensOf(MarkdownTokenKind.italic), hasLength(1));
      expect(document.tokensOf(MarkdownTokenKind.strike), hasLength(1));
    });

    test('does not parse escaped markers', () {
      final MarkdownEditingDocument document = parser.parse(
        r'\*not italic\* and \*\*not bold\*\*',
      );

      expect(document.tokens, isEmpty);
      expect(document.diagnostics, isEmpty);
    });

    test('does not parse intraword underscore delimiters', () {
      final MarkdownEditingDocument document = parser.parse(
        'word_part_more и_ещё_текст',
      );

      expect(document.tokens, isEmpty);
    });

    test('keeps adjacent completed spans separate', () {
      final MarkdownEditingDocument document = parser.parse(
        '**first** and **second**',
      );

      expect(document.tokensOf(MarkdownTokenKind.bold), hasLength(2));
      expect(
        document
            .tokensOf(MarkdownTokenKind.bold)
            .map((MarkdownToken token) => token.contentRange),
        <EditorRange>[
          const EditorRange(start: 2, end: 7),
          const EditorRange(start: 16, end: 22),
        ],
      );
    });

    test('reports unclosed formatting without changing its source range', () {
      final MarkdownEditingDocument document = parser.parse('Before **draft');
      final MarkdownToken token = _only(document, MarkdownTokenKind.bold);

      expect(token.isComplete, isFalse);
      expect(token.rawRange, const EditorRange(start: 7, end: 14));
      expect(token.contentRange, const EditorRange(start: 9, end: 14));
      expect(token.closingMarkerRange, isNull);
      expect(document.diagnostics, const <MarkdownEditingDiagnostic>[
        MarkdownEditingDiagnostic(
          kind: MarkdownEditingDiagnosticKind.unclosedInlineDelimiter,
          range: EditorRange(start: 7, end: 9),
        ),
      ]);
    });

    test('keeps U+FFFC as a single opaque code unit in ranges', () {
      const String text = '**\uFFFC😀**';
      final MarkdownToken token = _only(
        parser.parse(text),
        MarkdownTokenKind.bold,
      );

      expect(token.contentRange, const EditorRange(start: 2, end: 5));
      expect(
        text.substring(token.contentRange.start, token.contentRange.end),
        '\uFFFC😀',
      );
    });
  });

  group('MarkdownEditingParser code precedence', () {
    test('does not parse formatting inside inline code', () {
      final MarkdownEditingDocument document = parser.parse(
        '`**raw**` **bold**',
      );

      expect(document.tokensOf(MarkdownTokenKind.inlineCode), hasLength(1));
      expect(document.tokensOf(MarkdownTokenKind.bold), hasLength(1));
      expect(
        _only(document, MarkdownTokenKind.bold).rawRange,
        const EditorRange(start: 10, end: 18),
      );
    });

    test('does not parse formatting or blocks inside fenced code', () {
      final MarkdownEditingDocument document = parser.parse(
        '```dart\n**raw**\n# raw\n```\n# heading',
      );

      expect(document.tokensOf(MarkdownTokenKind.fencedCode), hasLength(1));
      expect(document.tokensOf(MarkdownTokenKind.bold), isEmpty);
      expect(document.tokensOf(MarkdownTokenKind.heading), hasLength(1));
    });

    test(
      'does not mistake a language-tagged source line for a closing fence',
      () {
        final MarkdownEditingDocument document = parser.parse(
          '```dart\nprint(1)\n```dart\nprint(2)\n```',
        );
        final MarkdownToken fence = _only(
          document,
          MarkdownTokenKind.fencedCode,
        );

        expect(fence.isComplete, isTrue);
        expect(fence.rawRange, const EditorRange(start: 0, end: 37));
      },
    );

    test('reports an unclosed fence and protects the remaining source', () {
      final MarkdownEditingDocument document = parser.parse('```\n**raw**');

      expect(_only(document, MarkdownTokenKind.fencedCode).isComplete, isFalse);
      expect(document.tokensOf(MarkdownTokenKind.bold), isEmpty);
      expect(
        document.diagnostics.single.kind,
        MarkdownEditingDiagnosticKind.unclosedFence,
      );
    });
  });

  group('MarkdownEditingParser blocks', () {
    test('recognizes headings, quotes and both list forms', () {
      final MarkdownEditingDocument document = parser.parse(
        '# title\n> reply\n- one\n12. twelve',
      );

      final MarkdownToken heading = _only(document, MarkdownTokenKind.heading);
      expect(heading.level, 1);
      expect(heading.contentRange, const EditorRange(start: 2, end: 7));
      expect(_only(document, MarkdownTokenKind.quote).contentRange.start, 10);
      expect(document.tokensOf(MarkdownTokenKind.bulletedList), hasLength(1));
      expect(
        _only(document, MarkdownTokenKind.orderedList).orderedListNumber,
        12,
      );
    });

    test('preserves CRLF source offsets', () {
      final MarkdownEditingDocument document = parser.parse('## one\r\n> two');
      final MarkdownToken heading = _only(document, MarkdownTokenKind.heading);
      final MarkdownToken quote = _only(document, MarkdownTokenKind.quote);

      expect(heading.rawRange, const EditorRange(start: 0, end: 6));
      expect(quote.rawRange, const EditorRange(start: 8, end: 13));
    });
  });
}

MarkdownToken _only(MarkdownEditingDocument document, MarkdownTokenKind kind) =>
    document.tokensOf(kind).single;
