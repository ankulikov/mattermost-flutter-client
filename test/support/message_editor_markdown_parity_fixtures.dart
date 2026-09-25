import 'package:mattermost_flutter/src/ui/messages/editor/markdown_editing_document.dart';

/// Completed Markdown constructs supported by both the editing parser and the
/// read-only Mattermost renderer.
///
/// This intentionally excludes unclosed and escaped syntax: the editor parses
/// those tolerantly for editability, while renderer parity is meaningful only
/// for completed constructs in the supported MVP subset.
class MessageEditorMarkdownParityFixture {
  const MessageEditorMarkdownParityFixture({
    required this.name,
    required this.source,
    required this.tokenKinds,
    required this.renderedText,
  });

  final String name;
  final String source;
  final List<MarkdownTokenKind> tokenKinds;
  final String renderedText;
}

const List<MessageEditorMarkdownParityFixture>
messageEditorMarkdownParityFixtures = <MessageEditorMarkdownParityFixture>[
  MessageEditorMarkdownParityFixture(
    name: 'bold',
    source: '**bold**',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.bold],
    renderedText: 'bold',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'italic',
    source: '*italic*',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.italic],
    renderedText: 'italic',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'bold italic',
    source: '***both***',
    tokenKinds: <MarkdownTokenKind>[
      MarkdownTokenKind.bold,
      MarkdownTokenKind.italic,
    ],
    renderedText: 'both',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'strikethrough',
    source: '~~strike~~',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.strike],
    renderedText: 'strike',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'inline code',
    source: '`inline code`',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.inlineCode],
    renderedText: 'inline code',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'fenced code',
    source: '```dart\nfinal answer = 42;\n```',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.fencedCode],
    renderedText: 'final answer = 42;',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'heading',
    source: '### Heading',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.heading],
    renderedText: 'Heading',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'quote',
    source: '> Quoted message',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.quote],
    renderedText: 'Quoted message',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'bulleted list',
    source: '- Bullet item',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.bulletedList],
    renderedText: 'Bullet item',
  ),
  MessageEditorMarkdownParityFixture(
    name: 'ordered list',
    source: '12. Ordered item',
    tokenKinds: <MarkdownTokenKind>[MarkdownTokenKind.orderedList],
    renderedText: 'Ordered item',
  ),
];
