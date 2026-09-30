# Message composer

Channels and threads share `MessageComposer`. It sends ordinary Mattermost
Markdown, supports formatting controls and inline atoms, and keeps a failed
draft available for correction or retry.

## Send behavior

Posts and replies use `POST /api/v4/posts`. Replies include `root_id`. The
composer creates `pending_post_id` and reuses it when the same failed draft is
retried manually. A send in progress blocks duplicate submission.

Enter sends the message. Shift+Enter inserts a line break. The draft clears
only after a successful REST response. A failure leaves the draft and shows a
non-blocking error.

## Live Markdown editing

The composer stores raw Markdown in one `TextEditingValue`. That value is the
wire representation, except for the existing copy, cut, and send serialization
of mention and custom-emoji atoms. The editor never round-trips text through a
rendered Markdown document and never normalizes spacing, list numbers, or
delimiters.

`MessageEditorController` owns the native editing value, selection, and IME
composing range. Its parser and edit commands are pure Dart. Live Preview, the
default mode, styles completed Markdown in the same buffer. Inactive markers
remain in the span tree with zero visual advance, so
`InlineSpan.toPlainText()` still matches the raw source. List prefixes such as
`- `, `* `, and `1. ` remain visible to preserve natural indentation.

Markers stay visible while the selection or IME range touches their token.
Unrecognized syntax, escaped content, and Markdown inside code ranges remain
literal source. The controller has a source mode, but the composer does not yet
expose a user preference for it.

## Formatting controls

The toolbar applies source-preserving commands for bold, italic,
strikethrough, heading, code, quote, bulleted list, and ordered list. Compact
layouts move the less common block commands into an overflow menu. Choosing a
command returns focus to the editor and preserves its selection.

The tolerant editing parser covers bold, italic, strikethrough, inline and
fenced code, headings, quotes, and ordered and bulleted lists. The read-only
renderer supports a wider Mattermost dialect; unsupported editing syntax still
passes through unchanged.

## Inline atoms and suggestions

Selected users, user groups, and custom emoji occupy one atomic position in the
editing projection. Copy, cut, and send convert them back to `@username`,
`@group-handle`, or `:emoji_name:`. The caret cannot enter the visual label.

Mention and emoji suggestions belong to the active composer. Moving the caret,
changing the destination, closing the composer, or starting a newer query
cancels work that is no longer relevant.

## Relevant code

- `lib/src/ui/messages/message_editor_controller.dart`
- `lib/src/ui/messages/editor/`
- `lib/src/ui/messages/widgets/message_composer.dart`
- `lib/src/ui/messages/widgets/message_formatting_toolbar.dart`
