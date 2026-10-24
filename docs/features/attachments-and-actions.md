# Attachments and interactive messages

Mattermost posts can carry uploaded files and legacy rich attachments. Both map
into domain models, but they remain separate because their wire formats and
interactions differ.

## Uploaded files

`PostMetadata.files` maps to shared `PostAttachment` entities. Attachment data
is not stored locally. Thumbnails, previews, and originals load through
authenticated `MattermostApi` requests; widgets never receive a token or a raw
HTTP client.

New posts and replies upload selected files through the authenticated API and
pass their ordered IDs in `file_ids` when creating the post. Upload state and
picked sources are never persisted. Removing a completed tile detaches its ID
from the pending post; the public API does not provide immediate draft-file
deletion.

The composer also accepts copied files and clipboard images through the same
upload contract. The clipboard adapter stays outside presentation code. Native
desktop files preserve the source name and extension; image-only clipboard
data is represented as PNG. Web support is limited to images, and Android
content URIs currently require a usable image representation.

A single image receives a large preview. Multiple files use compact cards, and
the full-screen viewer pages through images from one post. Images support pinch
zoom and panning up to 5x; page swiping pauses while an image is enlarged, and
the transform resets when the page changes. Saving the original calls a
platform file-saver through a domain contract. Sandboxed macOS builds write
only to a user-selected location, and iOS exports saved documents to the Files
app.

## Legacy rich attachments

The transport layer reads `props.attachments` without allowing one malformed
child to discard valid siblings. It maps valid attachments, fields, actions,
and options to immutable `RichAttachment` domain values. Unknown raw props stay
on the data side. `integration.context` is neither decoded nor exposed, and an
action's `cookie` remains an opaque value returned unchanged to the server.

`MessageContent` renders the same card in channels, threads, permalinks, search,
and Inbox. Supported action types are buttons and selects. Unknown types remain
unknown instead of being guessed.

## Action execution

1. Auto-disposed presentation state disables only the initiating control.
2. `PostActionRepository` accepts the opaque cookie and selected value.
3. The data repository calls
   `POST /posts/{post_id}/actions/{action_id}` through `MattermostApi`.
4. After a successful dispatch, it always refreshes the post with
   `GET /posts/{post_id}` and returns the authoritative post plus a validated
   `goto_location`.
5. The open snapshot replaces the post by ID through the shared merge policy.

System-backed selects use server-side `POST /users/search` or
`POST /channels/search`. Results are capped at 50, and superseded requests are
canceled with their provider. The UI submits a Mattermost ID as
`selected_option`.

Ephemeral action feedback is matched to the pending control by scope, post,
action, and expected channel or root. It lives only in auto-disposed screen
state, is absent from logs and Drift, and is not reconstructed after a
reconnect. Unmatched or expired feedback is discarded.

## Fixture contract

Fixtures under `test/fixtures/legacy_attachments/` contain complete post
responses with rich attachments in `props.attachments`. The malformed fixture
keeps valid and invalid attachments, fields, actions, and options side by side
to verify independent decoding. `action_api_response.json` models the response
from `POST /api/v4/posts/{post_id}/actions/{action_id}`.

| Wire object | Supported fields |
| --- | --- |
| Attachment | `fallback`, `color`, `pretext`, `author_name`, `author_link`, `author_icon`, `title`, `title_link`, `text`, `fields`, `image_url`, `thumb_url`, `footer`, `footer_icon`, `ts`, `actions` |
| Field | `title`, `value`, `short` |
| Action | `id`, `type`, `name`, `tooltip`, `style`, `disabled`, `data_source`, `options`, `default_option`, `cookie` |
| Option | `text`, `value` |
| Action response | `status`, `trigger_id`, `goto_location` |

## Relevant code

- `lib/src/ui/messages/widgets/message_attachments.dart`
- `lib/src/ui/messages/widgets/rich_attachments.dart`
- `lib/src/ui/messages/post_action_controller.dart`
- `lib/src/data/repositories/mattermost_post_action_repository.dart`
- `test/fixtures/legacy_attachments/`
