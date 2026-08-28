# Mattermost Markdown rendering

`MattermostMarkdown` is the shared renderer for channel messages and thread
posts. It uses `flutter_markdown_plus` as the GFM parser/widget layer and adds
the Mattermost-specific behavior documented in the official
[Format messages](https://docs.mattermost.com/end-user-guide/collaborate/format-messages.html)
guide.

## Compatibility matrix

| Documented feature | Support | Implementation |
| --- | --- | --- |
| Italic, bold, bold-italic, strikethrough | Yes | GFM emphasis and deletion syntax |
| Labeled and automatic links | Yes | GFM links; only `http`, `https`, and `mailto` can be opened |
| `~channel` links | Yes | Custom inline syntax selects a loaded channel by its server name |
| ATX and Setext headings, levels 1–6 | Yes | GFM/CommonMark headings |
| Bulleted, nested, ordered, start-number, and task lists | Yes | GFM lists and task-list checkboxes |
| Fenced and four-space-indented code blocks | Yes | Wrapping selectable block with Copy action |
| Syntax highlighting and every documented language alias | Yes | `highlight`; aliases are normalized explicitly and regression-tested |
| Inline code | Yes | GFM code spans |
| Inline images and hover title | Yes | HTTP(S) images; relative URLs resolve against the active server |
| Linked inline images | Yes | GFM nested image links |
| `=widthxheight` and `=width` image sizing | Yes | Mattermost pre-parser; height is capped at 500 px |
| Horizontal lines | Yes | GFM horizontal rules |
| Block quotes | Yes | GFM blockquotes with theme-aware styling |
| Tables and column alignment | Yes | Width-constrained GFM tables with wrapping cells |
| Inline `$LaTeX$` | Yes | `flutter_markdown_plus_latex` |
| Fenced `latex` formulas | Yes | Custom block syntax plus `flutter_markdown_plus_latex` |
| Unicode emoji and standard `:shortcode:` emoji | Yes | Unicode plus Dart Markdown `EmojiSyntax` |
| Custom `:emoji_name:` emoji | Yes | Post metadata plus authenticated, account-scoped image cache |

The Mattermost documentation explicitly says that HTML line breaks in table
cells are unsupported. `flutter_markdown_plus` does not render inline HTML,
which is therefore compatible with the documented message dialect and also
avoids passing server-provided HTML through to a platform renderer.

## Security and performance

- Server-provided images can load only `http` and `https`; local files,
  `data:` URLs, assets, and executable schemes are rejected.
- Link activation accepts `http`, `https`, and `mailto` only. Relative links
  resolve against the authenticated Mattermost server.
- Syntax highlighting is bounded to 20,000 characters per code block. Larger
  blocks remain selectable monospace text and keep the Copy action.
- Post bodies contain no nested scrollables: tables and code wrap to the post
  width, and oversized formulas scale down. Selection is provided by one
  non-scrolling `SelectionArea` around the rendered body.
- Soft line breaks are preserved because Mattermost users create message line
  breaks with Shift+Enter.
- Custom emoji keep their shortcode as an immediate loading/error fallback.
  Image bytes are cached separately from Markdown parsing and capped at 5000
  account-scoped objects.

## Dependencies

- `flutter_markdown_plus`: maintained cross-platform Markdown parser/widgets.
- `flutter_math_fork`: KaTeX-style formula widgets used by the Markdown
  extension without introducing a nested formula scroller.
- `highlight`: pure-Dart grammars covering the language and alias list in the
  Mattermost guide.
- `url_launcher`: maintained Flutter plugin for external links on Android,
  iOS, Web, macOS, and Windows.

Code-theme selection (GitHub, Solarized, and Monokai) and automatic image
collapse/expand are Mattermost display preferences, not Markdown syntax. The
renderer follows the app's light/dark theme and enforces the documented 500 px
image cap; those preferences should be wired when the settings feature exists.
