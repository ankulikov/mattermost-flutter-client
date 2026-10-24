# Message composer

Channels and threads share `MessageComposer`. Its quick mode sends ordinary
Mattermost Markdown with file upload and a full-editor switch, while its full
editor exposes every formatting control. Both modes use the same editing
buffer and keep a failed draft available for correction or retry.

## Send behavior

Posts and replies use `POST /api/v4/posts`. Replies include `root_id`. The
composer creates `pending_post_id` and reuses it when the same failed draft is
retried manually. A send in progress blocks duplicate submission.

The paperclip selects up to five files per post. Each selection starts one
`POST /api/v4/files` request per file, with at most two running together. The
composer keeps ordered file tiles and server-confirmed IDs in volatile state
scoped to the account, channel, and thread root. Send stays unavailable while
any tile is queued, uploading, finalizing, or failed. A failed tile must be
retried or removed. Attachment-only posts are supported. A failed post keeps
its text, file IDs, and pending post ID for manual retry without reuploading.
Removing or closing a composer cancels its in-flight requests.

When the message field is focused, the platform paste shortcut reads copied
files before text. Copied files retain their names, extensions, and bytes;
an image without a file path gets a timestamped name such as
`clipboard_2026_10_24_10_20_30.png`. Pasted files use
the same volatile upload queue, five-file limit, retries, and send gate as
paperclip selections. If the clipboard has no supported file content, paste
inserts plain text at the selection. The quick and full editors share this
behavior. macOS copies security-scoped clipboard files into app-owned temporary
storage and removes each copy when its upload tile is done. The current adapter
reads file paths on other desktop platforms and clipboard images
on every supported platform. Web exposes images but not copied file paths.
Android keyboard clipboard history inserts images through Flutter's content
insertion callback. The composer accepts supported image MIME types and adds
the provided bytes to the same upload queue with a timestamped filename.
Android file clipboard URIs still require a usable image representation when
read through the shortcut path.

Enter sends the message. Shift+Enter inserts a line break. The draft clears
only after a successful REST response. A failure leaves the draft and shows a
non-blocking error.

## Edit behavior

The author can choose Edit from a message's pointer menu or touch action sheet
in a channel or thread. The shared composer swaps in that post's raw Markdown,
retaining the previous unsent draft and uploaded file tiles for restoration.
Quick mode and the full editor use the same edit buffer. Cancel and a successful
save restore the draft; a successful save leaves the composer unfocused, while
a failed save keeps the attempted text for retry.
Attachments cannot be changed through this text-edit flow.

Edits use `PUT /api/v4/posts/{post_id}/patch` with only `message`. The partial
update preserves server-owned fields and existing attachments; the full post
update endpoint treats omitted fields as blank. The server enforces `edit_post`
permission and may reject an edit based on its configured edit time limit.
Mattermost does not send new mention or desktop notifications for an edit.
The returned post replaces the open channel or thread projection by revision;
realtime `post_edited` continues to reconcile other open views.

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

## Composer modes

The quick composer keeps the message field, file upload, full-editor switch,
and send action visible without a formatting toolbar. The full editor opens as
a constrained modal at medium and expanded widths and as a full-screen dialog
at compact widths. Closing it preserves the same draft, selection, attachments,
and Markdown source in the quick composer. A successful send closes the full
editor and clears the shared draft through the normal send flow.

## Formatting controls

The full-editor toolbar applies source-preserving commands for bold, italic,
strikethrough, heading, labeled links, code, quote, bulleted list, and ordered
list. Compact full-editor layouts wrap the toolbar so every command remains
visible. Other compact toolbar consumers may move less common commands into an
overflow menu. Choosing a command returns focus to the editor and preserves its
selection. Ctrl/Command+Alt+K applies the labeled-link command.

The tolerant editing parser covers bold, italic, strikethrough, labeled links,
inline and fenced code, headings, quotes, and ordered and bulleted lists. In
Live Preview, a completed `[label](destination)` renders its label in place and
reveals its source syntax while the selection or IME range touches it. The
read-only renderer supports a wider Mattermost dialect; unsupported editing
syntax still passes through unchanged.

## Inline atoms and suggestions

Selected users, user groups, and custom emoji occupy one atomic position in the
editing projection. Copy, cut, and send convert them back to `@username`,
`@group-handle`, or `:emoji_name:`. The caret cannot enter the visual label.

Mention and emoji suggestions belong to the active composer. Moving the caret,
changing the destination, closing the composer, or starting a newer query
cancels work that is no longer relevant.

Quick mode and the full editor expose the same mention, user-group, and emoji
autocomplete behavior. The full editor keeps suggestions inside its editing
surface: the panel is capped at 560 px on wider panes and uses the available
width and a bounded portion of the editor height on compact panes. Enter chooses
the highlighted suggestion before sending; arrows, Tab for mentions, and Escape
retain their quick-composer behavior.

## Relevant code

- `lib/src/ui/messages/message_editor_controller.dart`
- `lib/src/ui/messages/editor/`
- `lib/src/ui/messages/widgets/message_composer.dart`
- `lib/src/ui/messages/widgets/full_message_editor.dart`
- `lib/src/ui/messages/widgets/message_formatting_toolbar.dart`
