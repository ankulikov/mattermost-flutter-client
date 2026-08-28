import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:highlight/highlight.dart' as syntax;
import 'package:markdown/markdown.dart' as md;
import 'package:mattermost_flutter/src/core/ui/mattermost_markdown_strings.dart';
import 'package:url_launcher/url_launcher.dart';

typedef MattermostLinkLauncher = Future<bool> Function(Uri uri);
typedef MattermostInlineReplacementBuilder =
    Widget Function(BuildContext context, String value, TextStyle textStyle);

/// Declarative hook for replacing inline message tokens with widgets.
///
/// Emoji are the first consumer. Future enrichments such as `@username` can
/// use the same parser/builder boundary without adding feature dependencies to
/// the shared Markdown renderer.
final class MattermostInlineReplacement {
  const MattermostInlineReplacement({
    required this.elementName,
    required this.pattern,
    required this.builder,
    this.valueGroup = 1,
    this.startCharacter,
    this.shouldReplace,
    this.fallbackText,
  });

  final String elementName;
  final String pattern;
  final int valueGroup;
  final int? startCharacter;
  final bool Function(String value)? shouldReplace;
  final String? Function(String value)? fallbackText;
  final MattermostInlineReplacementBuilder builder;
}

/// Renders the Markdown dialect documented for Mattermost messages.
///
/// Server-provided images are restricted to HTTP(S). Relative image and link
/// destinations are resolved against [serverUrl], while local-file, data, and
/// executable URL schemes are never opened.
class MattermostMarkdown extends StatefulWidget {
  const MattermostMarkdown({
    required this.data,
    this.serverUrl,
    this.onTapChannel,
    this.linkLauncher,
    this.textStyle,
    this.inlineReplacements = const <MattermostInlineReplacement>[],
    super.key,
  });

  final String data;
  final Uri? serverUrl;
  final ValueChanged<String>? onTapChannel;
  final MattermostLinkLauncher? linkLauncher;
  final TextStyle? textStyle;
  final List<MattermostInlineReplacement> inlineReplacements;

  @override
  State<MattermostMarkdown> createState() => _MattermostMarkdownState();

  static final List<md.BlockSyntax> _mattermostBlockSyntaxes = <md.BlockSyntax>[
    const _MattermostLatexFenceSyntax(),
    ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  ];
  static final List<md.InlineSyntax> _mattermostInlineSyntaxes =
      <md.InlineSyntax>[
        _MattermostChannelLinkSyntax(),
        _MattermostInlineLatexSyntax(),
        md.EmojiSyntax(),
        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
      ];
}

class _MattermostMarkdownState extends State<MattermostMarkdown> {
  late String _preparedData;
  ThemeData? _cachedTheme;
  TextStyle? _cachedBodyStyle;
  MarkdownStyleSheet? _cachedStyleSheet;
  Map<String, MarkdownElementBuilder>? _cachedBuilders;
  late md.ExtensionSet _extensionSet;

  @override
  void initState() {
    super.initState();
    _preparedData = prepareMattermostMarkdown(widget.data);
    _extensionSet = _buildExtensionSet(widget.inlineReplacements);
  }

  @override
  void didUpdateWidget(covariant MattermostMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) {
      _preparedData = prepareMattermostMarkdown(widget.data);
    }
    if (!identical(widget.inlineReplacements, oldWidget.inlineReplacements)) {
      _extensionSet = _buildExtensionSet(widget.inlineReplacements);
      _cachedTheme = null;
    }
    if (widget.textStyle != oldWidget.textStyle ||
        widget.serverUrl != oldWidget.serverUrl) {
      _cachedTheme = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final TextStyle bodyStyle = widget.textStyle ?? theme.textTheme.bodyMedium!;
    if (!identical(theme, _cachedTheme) || bodyStyle != _cachedBodyStyle) {
      _cachedTheme = theme;
      _cachedBodyStyle = bodyStyle;
      _cachedStyleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: bodyStyle,
        blockSpacing: 8,
        a: bodyStyle.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
          decorationColor: colors.primary,
        ),
        code: bodyStyle.copyWith(
          fontFamily: 'monospace',
          fontSize: (bodyStyle.fontSize ?? 14) * 0.9,
          backgroundColor: colors.surfaceContainerHighest,
        ),
        h1: theme.textTheme.headlineSmall,
        h2: theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        h4: theme.textTheme.titleSmall,
        h5: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        h6: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        tableColumnWidth: const FlexColumnWidth(),
        tableScrollbarThumbVisibility: false,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
      );
      _cachedBuilders = <String, MarkdownElementBuilder>{
        'latex': _MattermostLatexBuilder(textStyle: bodyStyle),
        'pre': _MattermostCodeBlockBuilder(theme: theme),
        for (final MattermostInlineReplacement replacement
            in widget.inlineReplacements)
          replacement.elementName: _MattermostInlineReplacementBuilder(
            replacement: replacement,
            textStyle: bodyStyle,
          ),
      };
    }

    return SelectionArea(
      child: MarkdownBody(
        data: _preparedData,
        softLineBreak: true,
        extensionSet: _extensionSet,
        styleSheet: _cachedStyleSheet,
        imageBuilder: _buildImage,
        builders: _cachedBuilders!,
        onTapLink: (String text, String? href, String title) {
          if (href == null) return;
          if (href.startsWith(_MattermostChannelLinkSyntax.schemePrefix)) {
            final String channelName = Uri.decodeComponent(
              href.substring(_MattermostChannelLinkSyntax.schemePrefix.length),
            );
            widget.onTapChannel?.call(channelName);
            return;
          }
          unawaited(_openExternalLink(context, href));
        },
      ),
    );
  }

  md.ExtensionSet _buildExtensionSet(
    List<MattermostInlineReplacement> replacements,
  ) => md.ExtensionSet(
    MattermostMarkdown._mattermostBlockSyntaxes,
    <md.InlineSyntax>[
      ...replacements.map(_MattermostInlineReplacementSyntax.new),
      ...MattermostMarkdown._mattermostInlineSyntaxes,
    ],
  );

  Widget _buildImage(Uri source, String? title, String? alt) {
    final String? encodedSize = source.queryParameters[_imageSizeParameter];
    final ({double? width, double? height}) dimensions = _parseImageSize(
      encodedSize,
    );
    final Uri cleanSource = _withoutImageSizeParameter(source);
    final Uri? resolved = _resolveHttpUri(cleanSource);
    if (resolved == null) {
      return _ImageError(alt: alt);
    }

    final Widget image = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 500),
      child: Image.network(
        resolved.toString(),
        width: dimensions.width,
        height: dimensions.height,
        fit: BoxFit.contain,
        semanticLabel: alt,
        errorBuilder: (_, _, _) => _ImageError(alt: alt),
      ),
    );
    if (title == null || title.isEmpty) return image;
    return Tooltip(message: title, child: image);
  }

  Future<void> _openExternalLink(BuildContext context, String href) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final Uri? parsed = Uri.tryParse(href);
    if (parsed == null) {
      _showLinkError(messenger);
      return;
    }
    final Uri? resolved = parsed.scheme.isEmpty
        ? _resolveHttpUri(parsed)
        : parsed;
    if (resolved == null ||
        !const <String>{
          'http',
          'https',
          'mailto',
        }.contains(resolved.scheme.toLowerCase())) {
      _showLinkError(messenger);
      return;
    }

    try {
      final bool opened = widget.linkLauncher == null
          ? await launchUrl(resolved)
          : await widget.linkLauncher!(resolved);
      if (!opened) _showLinkError(messenger);
    } on Object {
      _showLinkError(messenger);
    }
  }

  Uri? _resolveHttpUri(Uri uri) {
    final Uri resolved;
    if (uri.scheme.isEmpty) {
      final Uri? base = widget.serverUrl;
      if (base == null) return null;
      final Uri directoryBase = base.replace(
        path: base.path.endsWith('/') ? base.path : '${base.path}/',
      );
      resolved = directoryBase.resolveUri(uri);
    } else {
      resolved = uri;
    }
    return const <String>{
          'http',
          'https',
        }.contains(resolved.scheme.toLowerCase())
        ? resolved
        : null;
  }

  void _showLinkError(ScaffoldMessengerState? messenger) {
    messenger?.showSnackBar(
      const SnackBar(content: Text(MattermostMarkdownStrings.openLinkFailed)),
    );
  }
}

final class _MattermostInlineReplacementSyntax extends md.InlineSyntax {
  _MattermostInlineReplacementSyntax(this.replacement)
    : super(replacement.pattern, startCharacter: replacement.startCharacter);

  final MattermostInlineReplacement replacement;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String value = match[replacement.valueGroup]!;
    if (replacement.shouldReplace?.call(value) == false) {
      final String? fallback = replacement.fallbackText?.call(value);
      if (fallback != null) {
        parser.addNode(md.Text(fallback));
        return true;
      }
      parser.advanceBy(1);
      return false;
    }
    final md.Element element = md.Element.empty(replacement.elementName);
    element.attributes['value'] = value;
    parser.addNode(element);
    return true;
  }
}

final class _MattermostInlineReplacementBuilder extends MarkdownElementBuilder {
  _MattermostInlineReplacementBuilder({
    required this.replacement,
    required this.textStyle,
  });

  final MattermostInlineReplacement replacement;
  final TextStyle textStyle;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Text.rich(
    TextSpan(
      children: <InlineSpan>[
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: replacement.builder(
            context,
            element.attributes['value'] ?? '',
            preferredStyle ?? parentStyle ?? textStyle,
          ),
        ),
      ],
    ),
  );
}

class _ImageError extends StatelessWidget {
  const _ImageError({this.alt});

  final String? alt;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: alt?.isNotEmpty == true
        ? alt
        : MattermostMarkdownStrings.imageUnavailable,
    child: Icon(
      Icons.broken_image_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _MattermostChannelLinkSyntax extends md.InlineSyntax {
  _MattermostChannelLinkSyntax()
    : super(r'~([A-Za-z0-9][A-Za-z0-9_-]*)', startCharacter: 0x7e);

  static const String schemePrefix = 'mattermost-channel:';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    if (parser.pos > 0) {
      final String preceding = parser.source.substring(
        parser.pos - 1,
        parser.pos,
      );
      if (RegExp(r'[A-Za-z0-9_-]').hasMatch(preceding)) {
        parser.advanceBy(1);
        return false;
      }
    }

    final String channelName = match[1]!;
    final md.Element link = md.Element.text('a', '~$channelName');
    link.attributes['href'] =
        '$schemePrefix${Uri.encodeComponent(channelName)}';
    parser.addNode(link);
    return true;
  }
}

class _MattermostInlineLatexSyntax extends md.InlineSyntax {
  _MattermostInlineLatexSyntax()
    : super(
        r'\$((?:\\.|[^\\$\n])+?)\$(?=[\s?!.,:？！。，：]|$)',
        startCharacter: 0x24,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final md.Element latex = md.Element.text('latex', match[1]!);
    latex.attributes['MathStyle'] = 'text';
    parser.addNode(latex);
    return true;
  }
}

class _MattermostLatexFenceSyntax extends md.BlockSyntax {
  const _MattermostLatexFenceSyntax();

  @override
  RegExp get pattern => RegExp(
    r'^ {0,3}(`{3,})[ \t]*latex(?:[ \t]+[^\n]*)?$',
    caseSensitive: false,
  );

  @override
  md.Node parse(md.BlockParser parser) {
    final RegExpMatch opening = pattern.firstMatch(parser.current.content)!;
    final String fence = opening[1]!;
    final StringBuffer content = StringBuffer();
    parser.advance();
    final RegExp closing = RegExp('^ {0,3}`{${fence.length},}[ \\t]*\$');
    while (!parser.isDone && !closing.hasMatch(parser.current.content)) {
      if (content.isNotEmpty) content.writeln();
      content.write(parser.current.content);
      parser.advance();
    }
    if (!parser.isDone) parser.advance();

    final md.Element latex = md.Element.text('latex', content.toString());
    latex.attributes['MathStyle'] = 'display';
    return md.Element('p', <md.Node>[latex]);
  }
}

class _MattermostLatexBuilder extends MarkdownElementBuilder {
  _MattermostLatexBuilder({required this.textStyle});

  final TextStyle textStyle;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String source = element.textContent;
    if (source.isEmpty) return const SizedBox.shrink();
    final MathStyle mathStyle = element.attributes['MathStyle'] == 'display'
        ? MathStyle.display
        : MathStyle.text;
    final Widget formula = Math.tex(
      source,
      mathStyle: mathStyle,
      textStyle: textStyle,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: formula,
          ),
        );
      },
    );
  }
}

class _MattermostCodeBlockBuilder extends MarkdownElementBuilder {
  _MattermostCodeBlockBuilder({required this.theme});

  static const int _maxHighlightedCharacters = 20000;

  final ThemeData theme;

  @override
  bool isBlockElement() => true;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String source = element.textContent.endsWith('\n')
        ? element.textContent.substring(0, element.textContent.length - 1)
        : element.textContent;
    final String? declaredLanguage = _declaredLanguage(element);
    final String? language = declaredLanguage == null
        ? null
        : canonicalMattermostCodeLanguage(declaredLanguage);
    final TextStyle baseStyle = theme.textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      height: 1.35,
      color: theme.colorScheme.onSurface,
    );
    final TextSpan code =
        source.length <= _maxHighlightedCharacters && language != null
        ? _highlight(source, language, baseStyle, theme.brightness)
        : TextSpan(text: source, style: baseStyle);
    final ColorScheme colors = theme.colorScheme;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (declaredLanguage != null && declaredLanguage.isNotEmpty)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      declaredLanguage,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: MattermostMarkdownStrings.copyCode,
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: source));
                },
                icon: const Icon(Icons.content_copy, size: 17),
              ),
            ],
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text.rich(code, softWrap: true),
          ),
        ],
      ),
    );
  }

  String? _declaredLanguage(md.Element element) {
    if (element.children?.singleOrNull case final md.Element code) {
      final String? className = code.attributes['class'];
      if (className?.startsWith('language-') == true) {
        return className!.substring('language-'.length).trim();
      }
    }
    return null;
  }

  TextSpan _highlight(
    String source,
    String language,
    TextStyle baseStyle,
    Brightness brightness,
  ) {
    final syntax.Result result = syntax.highlight.parse(
      source,
      language: language,
    );
    return TextSpan(
      style: baseStyle,
      children: result.nodes
          ?.map((syntax.Node node) => _nodeSpan(node, brightness))
          .toList(growable: false),
    );
  }

  TextSpan _nodeSpan(syntax.Node node, Brightness brightness) {
    final Color? color = _syntaxColor(node.className, brightness);
    return TextSpan(
      text: node.value,
      style: color == null ? null : TextStyle(color: color),
      children: node.children
          ?.map((syntax.Node child) => _nodeSpan(child, brightness))
          .toList(growable: false),
    );
  }

  Color? _syntaxColor(String? className, Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    return switch (className) {
      'comment' ||
      'quote' => dark ? const Color(0xff8b949e) : const Color(0xff6a737d),
      'keyword' ||
      'selector-tag' ||
      'subst' => dark ? const Color(0xffff7b72) : const Color(0xffd73a49),
      'number' || 'literal' || 'variable' || 'template-variable' =>
        dark ? const Color(0xff79c0ff) : const Color(0xff005cc5),
      'string' ||
      'doctag' ||
      'regexp' => dark ? const Color(0xffa5d6ff) : const Color(0xff032f62),
      'title' ||
      'section' ||
      'selector-id' => dark ? const Color(0xffd2a8ff) : const Color(0xff6f42c1),
      'type' || 'class' || 'built_in' || 'builtin-name' =>
        dark ? const Color(0xffffa657) : const Color(0xffe36209),
      'attr' ||
      'attribute' ||
      'name' ||
      'tag' => dark ? const Color(0xff7ee787) : const Color(0xff22863a),
      'meta' ||
      'meta-keyword' ||
      'symbol' ||
      'bullet' => dark ? const Color(0xfff2cc60) : const Color(0xff735c0f),
      _ => null,
    };
  }
}

const String _imageSizeParameter = '__mattermost_image_size';

/// Converts the documented Mattermost `=width[xheight]` image suffix into an
/// internal query marker understood by [MattermostMarkdown]. Code spans and
/// fenced code blocks remain byte-for-byte unchanged.
@visibleForTesting
String prepareMattermostMarkdown(String source) {
  final List<String> lines = source.split('\n');
  String? openFence;
  for (int index = 0; index < lines.length; index += 1) {
    final String line = lines[index];
    final RegExpMatch? fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(line);
    if (fence != null) {
      final String marker = fence[1]!;
      if (openFence == null) {
        openFence = marker;
      } else if (marker.codeUnitAt(0) == openFence.codeUnitAt(0) &&
          marker.length >= openFence.length) {
        openFence = null;
      }
      continue;
    }
    if (openFence == null) lines[index] = _rewriteImageSizesOutsideCode(line);
  }
  return lines.join('\n');
}

String _rewriteImageSizesOutsideCode(String line) {
  final StringBuffer result = StringBuffer();
  int position = 0;
  while (position < line.length) {
    final int codeStart = line.indexOf('`', position);
    if (codeStart < 0) {
      result.write(_rewriteImageSizes(line.substring(position)));
      break;
    }
    result.write(_rewriteImageSizes(line.substring(position, codeStart)));
    int fenceLength = 1;
    while (codeStart + fenceLength < line.length &&
        line.codeUnitAt(codeStart + fenceLength) == 0x60) {
      fenceLength += 1;
    }
    final String fence = '`' * fenceLength;
    final int codeEnd = line.indexOf(fence, codeStart + fenceLength);
    if (codeEnd < 0) {
      result.write(line.substring(codeStart));
      break;
    }
    result.write(line.substring(codeStart, codeEnd + fenceLength));
    position = codeEnd + fenceLength;
  }
  return result.toString();
}

String _rewriteImageSizes(String source) => source.replaceAllMapped(
  RegExp(r'(!\[[^\]\n]*\]\()(\S+)\s+=(\d+)(?:x(\d+))?'),
  (Match match) {
    final String destination = match[2]!;
    final String size = match[4] == null
        ? match[3]!
        : '${match[3]}x${match[4]}';
    final int fragmentStart = destination.indexOf('#');
    final String beforeFragment = fragmentStart < 0
        ? destination
        : destination.substring(0, fragmentStart);
    final String fragment = fragmentStart < 0
        ? ''
        : destination.substring(fragmentStart);
    final String separator = beforeFragment.contains('?') ? '&' : '?';
    return '${match[1]}$beforeFragment$separator$_imageSizeParameter=$size$fragment';
  },
);

({double? width, double? height}) _parseImageSize(String? value) {
  if (value == null) return (width: null, height: null);
  final RegExpMatch? match = RegExp(r'^(\d+)(?:x(\d+))?$').firstMatch(value);
  if (match == null) return (width: null, height: null);
  final double? width = double.tryParse(match[1]!);
  final double? height = match[2] == null ? null : double.tryParse(match[2]!);
  return (
    width: width?.clamp(1, 4096).toDouble(),
    height: height?.clamp(1, 500).toDouble(),
  );
}

Uri _withoutImageSizeParameter(Uri source) {
  final Map<String, List<String>> remaining = Map<String, List<String>>.from(
    source.queryParametersAll,
  )..remove(_imageSizeParameter);
  if (remaining.isNotEmpty) {
    return source.replace(queryParameters: remaining);
  }
  final String raw = source.toString();
  final int queryStart = raw.indexOf('?');
  if (queryStart < 0) return source;
  final int fragmentStart = raw.indexOf('#', queryStart);
  return Uri.parse(
    fragmentStart < 0
        ? raw.substring(0, queryStart)
        : '${raw.substring(0, queryStart)}${raw.substring(fragmentStart)}',
  );
}

const Map<String, String> _mattermostLanguageAliases = <String, String>{
  'actionscript': 'actionscript',
  'as': 'actionscript',
  'as3': 'actionscript',
  'applescript': 'applescript',
  'bash': 'bash',
  'sh': 'bash',
  'clojure': 'clojure',
  'coffeescript': 'coffeescript',
  'coffescript': 'coffeescript',
  'coffee': 'coffeescript',
  'coffee-script': 'coffeescript',
  'cpp': 'cpp',
  'c++': 'cpp',
  'c': 'cpp',
  'cs': 'cs',
  'c#': 'cs',
  'csharp': 'cs',
  'css': 'css',
  'd': 'd',
  'dlang': 'd',
  'dart': 'dart',
  'delphi': 'delphi',
  'diff': 'diff',
  'patch': 'diff',
  'udiff': 'diff',
  'django': 'django',
  'dockerfile': 'dockerfile',
  'docker': 'dockerfile',
  'elixir': 'elixir',
  'ex': 'elixir',
  'exs': 'elixir',
  'erlang': 'erlang',
  'erl': 'erlang',
  'fortran': 'fortran',
  'fsharp': 'fsharp',
  'gcode': 'gcode',
  'go': 'go',
  'golang': 'go',
  'groovy': 'groovy',
  'handlebars': 'handlebars',
  'hbs': 'handlebars',
  'mustache': 'handlebars',
  'haskell': 'haskell',
  'hs': 'haskell',
  'haxe': 'haxe',
  'java': 'java',
  'javascript': 'javascript',
  'js': 'javascript',
  'json': 'json',
  'julia': 'julia',
  'jl': 'julia',
  'kotlin': 'kotlin',
  'less': 'less',
  'lisp': 'lisp',
  'lua': 'lua',
  'makefile': 'makefile',
  'make': 'makefile',
  'mf': 'makefile',
  'gnumake': 'makefile',
  'bsdmake': 'makefile',
  'markdown': 'markdown',
  'md': 'markdown',
  'mkd': 'markdown',
  'matlab': 'matlab',
  'm': 'matlab',
  'objectivec': 'objectivec',
  'objective_c': 'objectivec',
  'objc': 'objectivec',
  'ocaml': 'ocaml',
  'perl': 'perl',
  'pl': 'perl',
  'pascal': 'delphi',
  'pas': 'delphi',
  'pgsql': 'pgsql',
  'postgres': 'pgsql',
  'postgresql': 'pgsql',
  'php': 'php',
  'php3': 'php',
  'php4': 'php',
  'php5': 'php',
  'powershell': 'powershell',
  'posh': 'powershell',
  'puppet': 'puppet',
  'pp': 'puppet',
  'python': 'python',
  'py': 'python',
  'r': 'r',
  's': 'r',
  'ruby': 'ruby',
  'rb': 'ruby',
  'rust': 'rust',
  'rs': 'rust',
  'scala': 'scala',
  'scheme': 'scheme',
  'scss': 'scss',
  'smalltalk': 'smalltalk',
  'st': 'smalltalk',
  'squeak': 'smalltalk',
  'sql': 'sql',
  'stylus': 'stylus',
  'styl': 'stylus',
  'swift': 'swift',
  'latex': 'tex',
  'tex': 'tex',
  'text': 'plaintext',
  'typescript': 'typescript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'vbnet': 'vbnet',
  'vb': 'vbnet',
  'visualbasic': 'vbnet',
  'vbscript': 'vbscript',
  'verilog': 'verilog',
  'vhdl': 'vhdl',
  'html': 'xml',
  'xml': 'xml',
  'yaml': 'yaml',
  'yml': 'yaml',
};

@visibleForTesting
String? canonicalMattermostCodeLanguage(String declaredLanguage) =>
    _mattermostLanguageAliases[declaredLanguage.toLowerCase()];
