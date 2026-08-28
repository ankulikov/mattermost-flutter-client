# Custom emoji

Message rendering is metadata-first. `PostMetadata.emojis` supplies the custom
emoji id, name, and update timestamp with the post, so rendering normally needs
only `GET /emoji/{emoji_id}/image`. If metadata is absent, the repository falls
back to `GET /emoji/name/{emoji_name}` before loading the image.

Image bytes are temporary and never stored in Drift. The cache is scoped by
server/account, keyed by normalized name, id, and update timestamp, and bounded
to 5000 objects. The repository coalesces concurrent requests for the same
account/name. A cache miss does not block Markdown layout: the shortcode stays
visible until the inline image is ready, and remains visible after a failure.

The API also exposes paged listing (`GET /emoji`), search
(`POST /emoji/search`, maximum 200), autocomplete (`GET /emoji/autocomplete`,
maximum 100), and batch lookup (`POST /emoji/names`, maximum 200, Mattermost
9.2+). Those endpoints are intended for pickers and bulk discovery; message
rendering avoids them because post metadata is both cheaper and exact.

Custom emoji reaction buttons resolve their image through the same repository,
provider, and account-scoped byte cache as inline emoji. Reaction state itself
remains in the open channel or thread controller: a tap optimistically toggles
the current user and count, then rolls back if the Mattermost reactions API
request fails.
