import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/mattermost_system_emojis.g.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown.dart';
import 'package:mattermost_flutter/src/ui/messages/mattermost_markdown_strings.dart';

void main() {
  test('recognizes post permalinks only on the active Mattermost server', () {
    final Uri server = Uri.parse('https://chat.example.com/mattermost');

    expect(
      mattermostPostIdFromPermalink(
        uri: Uri.parse(
          'https://chat.example.com/mattermost/team-a/pl/post-123?x=1',
        ),
        serverUrl: server,
      ),
      'post-123',
    );
    expect(
      mattermostPostIdFromPermalink(
        uri: Uri.parse('https://other.example.com/team-a/pl/post-123'),
        serverUrl: server,
      ),
      isNull,
    );
    expect(
      mattermostPostIdFromPermalink(
        uri: Uri.parse('https://chat.example.com/team-a/pl/post-123'),
        serverUrl: server,
      ),
      isNull,
    );
  });

  testWidgets('routes same-server post links internally', (
    WidgetTester tester,
  ) async {
    String? openedPostId;
    Uri? launchedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MattermostMarkdown(
            data:
                '[message](https://chat.example.com/team-a/pl/post-123) '
                '[external](https://other.example.com/team-a/pl/post-456)',
            serverUrl: Uri.parse('https://chat.example.com'),
            onTapPostLink: (String postId) => openedPostId = postId,
            linkLauncher: (Uri uri) async {
              launchedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );

    _tapTextSpan(tester, 'message');
    await tester.pump();
    expect(openedPostId, 'post-123');
    expect(launchedUri, isNull);

    _tapTextSpan(tester, 'external');
    await tester.pump();
    expect(
      launchedUri,
      Uri.parse('https://other.example.com/team-a/pl/post-456'),
    );
  });

  test('uses Mattermost system emoji aliases generated from emoji.json', () {
    expect(mattermostSystemEmojis['large_green_circle'], '🟢');
    expect(mattermostSystemEmojis, isNot(contains('mattermost')));
  });

  test('rewrites Mattermost image dimensions outside code only', () {
    const String source = '''
![fixed](https://example.com/image.png =50x76 "hover")
![wide](/relative.png =120)
`![inline](https://example.com/code.png =1x2)`
```text
![block](https://example.com/code.png =3x4)
```
''';

    expect(
      prepareMattermostMarkdown(source),
      contains(
        '![fixed](https://example.com/image.png?'
        '__mattermost_image_size=50x76 "hover")',
      ),
    );
    expect(
      prepareMattermostMarkdown(source),
      contains('![wide](/relative.png?__mattermost_image_size=120)'),
    );
    expect(
      prepareMattermostMarkdown(source),
      contains('`![inline](https://example.com/code.png =1x2)`'),
    );
    expect(
      prepareMattermostMarkdown(source),
      contains('![block](https://example.com/code.png =3x4)'),
    );
  });

  test('recognizes every syntax-highlighting alias in Mattermost docs', () {
    const List<String> aliases = <String>[
      'actionscript',
      'as',
      'as3',
      'applescript',
      'bash',
      'sh',
      'clojure',
      'coffescript',
      'coffee',
      'coffee-script',
      'cpp',
      'c++',
      'c',
      'cs',
      'c#',
      'csharp',
      'css',
      'd',
      'dlang',
      'dart',
      'delphi',
      'diff',
      'patch',
      'udiff',
      'django',
      'dockerfile',
      'docker',
      'elixir',
      'ex',
      'exs',
      'erlang',
      'erl',
      'fortran',
      'fsharp',
      'gcode',
      'go',
      'golang',
      'groovy',
      'handlebars',
      'hbs',
      'mustache',
      'haskell',
      'hs',
      'haxe',
      'java',
      'javascript',
      'js',
      'json',
      'julia',
      'jl',
      'kotlin',
      'latex',
      'tex',
      'less',
      'lisp',
      'lua',
      'makefile',
      'make',
      'mf',
      'gnumake',
      'bsdmake',
      'markdown',
      'md',
      'mkd',
      'matlab',
      'm',
      'objectivec',
      'objective_c',
      'objc',
      'ocaml',
      'perl',
      'pl',
      'pascal',
      'pas',
      'pgsql',
      'postgres',
      'postgresql',
      'php',
      'php3',
      'php4',
      'php5',
      'powershell',
      'posh',
      'puppet',
      'pp',
      'python',
      'py',
      'r',
      's',
      'ruby',
      'rb',
      'rust',
      'rs',
      'scala',
      'scheme',
      'scss',
      'smalltalk',
      'st',
      'squeak',
      'sql',
      'stylus',
      'styl',
      'swift',
      'text',
      'typescript',
      'ts',
      'tsx',
      'vbnet',
      'vb',
      'visualbasic',
      'vbscript',
      'verilog',
      'vhdl',
      'html',
      'xml',
      'yaml',
      'yml',
    ];

    for (final String alias in aliases) {
      expect(
        canonicalMattermostCodeLanguage(alias),
        isNotNull,
        reason: 'Missing Mattermost code alias: $alias',
      );
    }
  });

  testWidgets('renders the documented Mattermost Markdown features', (
    WidgetTester tester,
  ) async {
    String? selectedChannel;
    Uri? launchedUri;
    MethodCall? clipboardCall;
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        clipboardCall = call;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MattermostMarkdown(
              serverUrl: Uri.parse('https://mattermost.example.com/team/'),
              onTapChannel: (String name) => selectedChannel = name,
              linkLauncher: (Uri uri) async {
                launchedUri = uri;
                return true;
              },
              data: r'''
# Heading

**bold** *italic* ***both*** ~~strike~~

- bullet
  - nested
- [x] completed

4. fourth
1. fifth

> quoted **bold** text

`inline code`

| Left | Right |
| :--- | ----: |
| A | B |

---

[Mattermost](https://mattermost.com) and ~roadmap and :smile:

```dart
void main() => print('hello');
```

$E = mc^2$

```latex
X_k = \sum_{n=0}^{N} x_n
```
''',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Heading', findRichText: true), findsOneWidget);
    expect(find.textContaining('bold', findRichText: true), findsWidgets);
    expect(find.textContaining('nested', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byTooltip(MattermostMarkdownStrings.copyCode), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MattermostMarkdown),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget.runtimeType.toString() == 'Math',
      ),
      findsNWidgets(2),
    );

    _tapTextSpan(tester, '~roadmap');
    await tester.pump();
    expect(selectedChannel, 'roadmap');

    _tapTextSpan(tester, 'Mattermost');
    await tester.pump();
    expect(launchedUri, Uri.parse('https://mattermost.com'));

    await tester.tap(find.byTooltip(MattermostMarkdownStrings.copyCode));
    await tester.pump();
    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, <String, Object>{
      'text': "void main() => print('hello');",
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('supports reusable inline replacements after standard emoji', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MattermostMarkdown(
            data: ':large_green_circle: :party_parrot:',
            inlineReplacements: <MattermostInlineReplacement>[
              MattermostInlineReplacement(
                elementName: 'test-emoji',
                pattern: r':([a-z0-9_+-]+):',
                startCharacter: 0x3a,
                shouldReplace: (String name) =>
                    !mattermostSystemEmojis.containsKey(name),
                fallbackText: (String name) => mattermostSystemEmojis[name],
                builder: (_, String name, _) => Text('custom=$name'),
              ),
            ],
          ),
        ),
      ),
    );

    final Finder inlineText = find.byWidgetPredicate((Widget widget) {
      if (widget case Text(textSpan: final InlineSpan span?)) {
        return span.toPlainText().contains('🟢') && _containsWidgetSpan(span);
      }
      return false;
    });

    expect(inlineText, findsOneWidget);
    expect(find.text('custom=party_parrot'), findsOneWidget);
  });

  testWidgets('blocks unsafe links and image schemes', (
    WidgetTester tester,
  ) async {
    int launchCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MattermostMarkdown(
            data: '[unsafe](javascript:alert(1)) ![secret](file:///etc/passwd)',
            linkLauncher: (Uri uri) async {
              launchCount += 1;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    _tapTextSpan(tester, 'unsafe');
    await tester.pump();
    expect(launchCount, 0);
    expect(find.text(MattermostMarkdownStrings.openLinkFailed), findsOneWidget);
  });

  testWidgets('resolves relative images and honors Mattermost dimensions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MattermostMarkdown(
            data: '![logo](/static/logo.png =50x76 "Logo")',
            serverUrl: Uri.parse('https://mattermost.example.com/team/'),
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 50);
    expect(image.height, 76);
    expect(
      (image.image as NetworkImage).url,
      'https://mattermost.example.com/static/logo.png',
    );
    expect(find.byTooltip('Logo'), findsOneWidget);
  });

  testWidgets('lays out at compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: MattermostMarkdown(
                data: '''
## Large text

| Column A | Column B |
| --- | --- |
| Long table value | Another long table value |

```typescript
const greeting = 'hello';
```

\$X_k = \\sum_{n=0}^{200} x_n \\cos(n) + \\frac{n^2}{n+1}\$
''',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Large text', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(MattermostMarkdown),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

bool _containsWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) {
    return true;
  }
  return span is TextSpan && span.children?.any(_containsWidgetSpan) == true;
}

void _tapTextSpan(WidgetTester tester, String text) {
  final Iterable<InlineSpan> spans = <InlineSpan>[
    ...find
        .byType(RichText)
        .evaluate()
        .map((Element element) => (element.widget as RichText).text),
    ...find
        .byType(SelectableText)
        .evaluate()
        .map((Element element) => (element.widget as SelectableText).textSpan!),
  ];
  for (final InlineSpan span in spans) {
    final TapGestureRecognizer? recognizer = _findTapRecognizer(span, text);
    if (recognizer != null) {
      recognizer.onTap?.call();
      return;
    }
  }
  fail('No tappable text span contained "$text".');
}

TapGestureRecognizer? _findTapRecognizer(InlineSpan span, String text) {
  if (span is! TextSpan) return null;
  if (span.toPlainText().contains(text)) {
    if (span.recognizer case final TapGestureRecognizer recognizer) {
      return recognizer;
    }
  }
  for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
    final TapGestureRecognizer? recognizer = _findTapRecognizer(child, text);
    if (recognizer != null) return recognizer;
  }
  return null;
}
