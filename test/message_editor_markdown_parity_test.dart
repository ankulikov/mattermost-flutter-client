import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';
import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_parser.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';

import 'support/message_editor_markdown_parity_fixtures.dart';

void main() {
  const MarkdownEditingParser parser = MarkdownEditingParser();

  test('parser recognizes every completed renderer parity fixture', () {
    for (final MessageEditorMarkdownParityFixture fixture
        in messageEditorMarkdownParityFixtures) {
      final MarkdownEditingDocument document = parser.parse(fixture.source);

      expect(document.diagnostics, isEmpty, reason: fixture.name);
      expect(
        document.tokens.map((MarkdownToken token) => token.kind),
        fixture.tokenKinds,
        reason: fixture.name,
      );
      expect(
        document.tokens.every((MarkdownToken token) => token.isComplete),
        isTrue,
        reason: fixture.name,
      );
    }
  });

  testWidgets('MattermostMarkdown renders every parser parity fixture', (
    WidgetTester tester,
  ) async {
    for (final MessageEditorMarkdownParityFixture fixture
        in messageEditorMarkdownParityFixtures) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MattermostMarkdown(data: fixture.source)),
        ),
      );
      await tester.pump();

      expect(
        find.text(fixture.renderedText, findRichText: true),
        findsOneWidget,
        reason: fixture.name,
      );
      expect(tester.takeException(), isNull, reason: fixture.name);
    }
  });
}
