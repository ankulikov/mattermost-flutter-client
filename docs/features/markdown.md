# Markdown rendering

`MattermostMarkdown` is the shared read-only renderer for channel messages,
thread replies, permalinks, search results, and Inbox previews. It uses
`flutter_markdown_plus` for GFM and adds the syntax and behavior Mattermost
documents in its [message formatting guide](https://docs.mattermost.com/end-user-guide/collaborate/format-messages.html).

## Compatibility

| Feature | Support | Implementation |
| --- | --- | --- |
| Italic, bold, bold italic, strikethrough | Yes | GFM emphasis and deletion syntax |
| Labeled and automatic links | Yes | GFM links; only `http`, `https`, and `mailto` open |
| `~channel` links | Yes | Custom inline syntax resolves a loaded channel by server name |
| ATX and Setext headings | Yes | CommonMark heading levels 1 through 6 |
| Bulleted, nested, ordered, start-number, and task lists | Yes | GFM lists and task checkboxes |
| Fenced and four-space code blocks | Yes | Selectable wrapping block with Copy action |
| Syntax highlighting and Mattermost aliases | Yes | `highlight` with explicit alias normalization |
| Inline code | Yes | GFM code spans |
| Inline images and hover titles | Yes | HTTP(S); relative URLs resolve against the active server |
| Linked inline images | Yes | Nested GFM image links |
| `=widthxheight` and `=width` image sizing | Yes | Mattermost pre-parser with a 500 px height cap |
| Horizontal rules and block quotes | Yes | GFM with theme-aware styling |
| Tables and alignment | Yes | Width-constrained tables with wrapping cells |
| Inline `$LaTeX$` | Yes | `flutter_markdown_plus_latex` |
| Fenced `latex` formulas | Yes | Custom block syntax and `flutter_markdown_plus_latex` |
| Unicode and standard `:shortcode:` emoji | Yes | Unicode plus a generated Mattermost dictionary |
| Custom emoji | Yes | Post metadata plus an authenticated account-scoped image cache |
| User mentions | Yes | Batched profile lookup and a profile-card link |

The composer may show mentions and custom emoji as visual atoms, but it
serializes them to canonical Mattermost text before the read path receives the
message. Rendering and editing therefore share the wire format without sharing
an editable AST.

Mattermost does not support HTML line breaks inside table cells. The renderer
does not execute inline HTML, which matches that dialect and avoids handing
server-provided HTML to a platform renderer.

## Links and permalinks

External activation accepts `http`, `https`, and `mailto`. Relative links
resolve against the authenticated server. Scheme-less links that begin with a
domain name are treated as HTTPS external links rather than server-relative
paths. A post permalink for that same origin uses the internal permalink route;
a look-alike link from another origin stays external.

## Security and performance

- Server images may use only `http` or `https`. Local files, assets, `data:`
  URLs, and executable schemes are rejected.
- Syntax highlighting is limited to 20,000 characters per block. Larger blocks
  remain selectable monospace text with Copy.
- Tables and code wrap to the post width. Oversized formulas scale down instead
  of adding nested scrolling.
- One non-scrolling `SelectionArea` preserves pointer selection and keyboard
  copying across the body.
- A touch-only interaction bridge opens the post thread or action sheet without
  breaking link activation. Mouse selection retains normal desktop behavior.
- Soft line breaks are preserved because Shift+Enter creates Mattermost message
  line breaks.
- Custom emoji keep their shortcode visible while image data loads or fails.
- Mention replacements remain text spans, so full display names wrap in narrow
  layouts and table cells.

The generated system shortcode map comes from a pinned Mattermost `emoji.json`
revision. The source JSON is not shipped as an application asset. To update the
map after selecting a new revision, run:

```sh
dart run tool/generate_mattermost_system_emojis.dart
```

## Dependencies

- `flutter_markdown_plus` supplies the cross-platform Markdown parser and widgets.
- `flutter_math_fork` renders KaTeX-style formulas.
- `highlight` supplies pure-Dart language grammars.
- `url_launcher` opens approved external links on every target platform.

## Relevant code

- `lib/src/ui/messages/mattermost_markdown.dart`
- `lib/src/domain/models/mattermost_system_emojis.g.dart`
- `tool/generate_mattermost_system_emojis.dart`
