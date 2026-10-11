import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_edit_command.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';

void main() {
  group('MarkdownEditCommands inline toggles', () {
    test('adds and removes bold while preserving the content selection', () {
      final MarkdownEditCommandResult added = MarkdownEditCommands.bold(
        'text',
        const EditorSelection(baseOffset: 0, extentOffset: 4),
      );
      final MarkdownEditCommandResult removed = MarkdownEditCommands.bold(
        added.text,
        added.selection,
      );

      expect(added.text, '**text**');
      expect(
        added.selection,
        const EditorSelection(baseOffset: 2, extentOffset: 6),
      );
      expect(removed.text, 'text');
      expect(
        removed.selection,
        const EditorSelection(baseOffset: 0, extentOffset: 4),
      );
    });

    test('inserts an empty pair for a collapsed selection', () {
      final MarkdownEditCommandResult result = MarkdownEditCommands.strike(
        'go',
        const EditorSelection.collapsed(1),
      );

      expect(result.text, 'g~~~~o');
      expect(result.selection, const EditorSelection.collapsed(3));
    });

    test('does not include outer whitespace in inline delimiters', () {
      final MarkdownEditCommandResult result = MarkdownEditCommands.italic(
        ' hello ',
        const EditorSelection(baseOffset: 0, extentOffset: 7),
      );

      expect(result.text, ' *hello* ');
      expect(
        result.selection,
        const EditorSelection(baseOffset: 2, extentOffset: 7),
      );
    });

    test('combines and removes bold and italic layers independently', () {
      final MarkdownEditCommandResult bold = MarkdownEditCommands.bold(
        'text',
        const EditorSelection(baseOffset: 0, extentOffset: 4),
      );
      final MarkdownEditCommandResult both = MarkdownEditCommands.italic(
        bold.text,
        bold.selection,
      );
      final MarkdownEditCommandResult italic = MarkdownEditCommands.bold(
        both.text,
        both.selection,
      );

      expect(both.text, '***text***');
      expect(italic.text, '*text*');
      expect(
        italic.selection,
        const EditorSelection(baseOffset: 1, extentOffset: 5),
      );
    });

    test('uses inline code for one line and fences for multiple lines', () {
      final MarkdownEditCommandResult inline = MarkdownEditCommands.code(
        'code',
        const EditorSelection(baseOffset: 0, extentOffset: 4),
      );
      final MarkdownEditCommandResult fenced = MarkdownEditCommands.code(
        'one\ntwo',
        const EditorSelection(baseOffset: 0, extentOffset: 7),
      );
      final MarkdownEditCommandResult unfenced = MarkdownEditCommands.code(
        fenced.text,
        fenced.selection,
      );

      expect(inline.text, '`code`');
      expect(fenced.text, '```\none\ntwo\n```');
      expect(unfenced.text, 'one\ntwo');
    });

    test('preserves a reversed selection direction', () {
      final MarkdownEditCommandResult result = MarkdownEditCommands.bold(
        'text',
        const EditorSelection(baseOffset: 4, extentOffset: 0),
      );

      expect(
        result.selection,
        const EditorSelection(baseOffset: 6, extentOffset: 2),
      );
    });

    test('adds and removes a labeled link while preserving its selection', () {
      final MarkdownEditCommandResult added = MarkdownEditCommands.link(
        'Mattermost',
        const EditorSelection(baseOffset: 0, extentOffset: 10),
      );
      final MarkdownEditCommandResult removed = MarkdownEditCommands.link(
        added.text,
        added.selection,
      );

      expect(added.text, '[Mattermost](url)');
      expect(
        added.selection,
        const EditorSelection(baseOffset: 1, extentOffset: 11),
      );
      expect(removed.text, 'Mattermost');
      expect(
        removed.selection,
        const EditorSelection(baseOffset: 0, extentOffset: 10),
      );
    });

    test('inserts empty link syntax at a collapsed selection', () {
      final MarkdownEditCommandResult result = MarkdownEditCommands.link(
        'go',
        const EditorSelection.collapsed(1),
      );

      expect(result.text, 'g[](url)o');
      expect(result.selection, const EditorSelection.collapsed(2));
    });
  });

  group('MarkdownEditCommands block toggles', () {
    test('adds and removes quote prefixes on every affected line', () {
      final MarkdownEditCommandResult added = MarkdownEditCommands.quote(
        'one\ntwo',
        const EditorSelection(baseOffset: 0, extentOffset: 7),
      );
      final MarkdownEditCommandResult removed = MarkdownEditCommands.quote(
        added.text,
        added.selection,
      );

      expect(added.text, '> one\n> two');
      expect(removed.text, 'one\ntwo');
      expect(
        removed.selection,
        const EditorSelection(baseOffset: 0, extentOffset: 7),
      );
    });

    test(
      'uses canonical bullet prefix and removes accepted marker variants',
      () {
        final MarkdownEditCommandResult added =
            MarkdownEditCommands.bulletedList(
              'one\ntwo',
              const EditorSelection(baseOffset: 0, extentOffset: 7),
            );
        final MarkdownEditCommandResult removed =
            MarkdownEditCommands.bulletedList(
              '* one\n+ two',
              const EditorSelection(baseOffset: 0, extentOffset: 11),
            );

        expect(added.text, '- one\n- two');
        expect(removed.text, 'one\ntwo');
      },
    );

    test('numbers ordered lines and removes multi-digit markers', () {
      final MarkdownEditCommandResult added = MarkdownEditCommands.orderedList(
        'one\ntwo\nthree',
        const EditorSelection(baseOffset: 0, extentOffset: 13),
      );
      final MarkdownEditCommandResult removed =
          MarkdownEditCommands.orderedList(
            '10. one\n11. two',
            const EditorSelection(baseOffset: 0, extentOffset: 15),
          );

      expect(added.text, '1. one\n2. two\n3. three');
      expect(removed.text, 'one\ntwo');
    });

    test('toggles the Mattermost default H3 prefix and handles CRLF', () {
      final MarkdownEditCommandResult added = MarkdownEditCommands.heading(
        'title\r\nnext',
        const EditorSelection(baseOffset: 0, extentOffset: 11),
      );
      final MarkdownEditCommandResult removed = MarkdownEditCommands.heading(
        added.text,
        added.selection,
      );

      expect(added.text, '### title\r\n### next');
      expect(removed.text, 'title\r\nnext');
    });

    test('does not add a duplicate prefix to an already matching line', () {
      final MarkdownEditCommandResult result = MarkdownEditCommands.quote(
        '> one\ntwo',
        const EditorSelection(baseOffset: 0, extentOffset: 9),
      );

      expect(result.text, '> one\n> two');
    });
  });
}
