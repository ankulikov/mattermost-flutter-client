# Mentions, reactions, and emoji

This feature covers mention resolution in displayed messages, composer
autocomplete, system and custom emoji, reactions, and the small durable list of
recently used emoji.

## Displayed mentions

The renderer collects unique `@username` handles and resolves them with a
single batch. Fresh profiles come from the account-scoped Drift cache. Expired
known profiles refresh through `/users/ids`; names missing from cache are
checked through `/users/usernames`. Only a confirmed user becomes a clickable
display-name mention. Unknown names and request failures leave the source text
unchanged.

The same handle set is checked with `POST /groups/names`. A confirmed user group
remains `@group-handle` instead of changing to a display name. Its link does not
yet open a group card or member list.

## Composer autocomplete

Autocomplete is network-first and scoped to the composer. Results from
`/users/autocomplete` and `/groups` are canceled when the caret, destination,
or query changes. They are not saved to Drift or merged into the profile cache.

Suggestions have separate sections for channel members, referenceable group
mentions, and users outside the channel. Groups request
`filter_allow_reference=true` and `include_member_count=true`. If the licensed
group endpoint is unavailable, user suggestions remain available.

Group ranking uses exact handle, handle prefix, display-name prefix, then a
case-insensitive handle comparison. Current-user group membership does not
affect suggestion ranking.

## Custom emoji

Post metadata maps custom emoji into the message's domain snapshot. Rendering
usually needs only authenticated `GET /emoji/{emoji_id}/image`; when metadata
is absent, the repository falls back to `GET /emoji/name/{emoji_name}`.

Image bytes use a temporary account-scoped cache capped at 5,000 objects. Keys
include name, ID, and `update_at`, and concurrent misses share one request.
Metadata results remain in repository memory for five minutes, with at most 50
search or page entries.

The picker searches the generated system catalog locally. Custom search uses
`POST /emoji/search` after a 500 ms debounce, cancels the old request, and
prevents stale results from replacing a newer query. Custom catalog pages use
`GET /emoji` in batches of 90.

The last 27 selected emoji are stored in the account-scoped `recent_emojis`
table. A row contains the shortcode and last-used timestamp, never a post ID or
message body. An upsert moves a repeated selection to the front and pruning
removes only the oldest entry beyond the limit.

## Reactions

Reaction buttons and inline custom emoji share the same provider and image
cache. Adding a reaction updates the open channel or thread optimistically,
then calls `POST /reactions`. Removing one calls
`DELETE /users/{user_id}/posts/{post_id}/reactions/{emoji_name}`. A failed
request rolls the local change back without replacing the displayed content.

The reaction picker is an anchored popover for precise pointer input and a
bottom sheet after a touch long press. It supports arrows, Enter, Escape,
pointer input, and responsive grid widths.

Each reaction retains the reactor user IDs supplied in post metadata. The open
message surface resolves those IDs through the user repository and shows the
display names in a tooltip on pointer hover or touch long press, with at most
two names on each line. A short touch still toggles the reaction; the
long-press tooltip uses platform haptic feedback.

## Relevant code

- `lib/src/features/mentions/`
- `lib/src/data/repositories/api_custom_emoji_repository.dart`
- `lib/src/data/database/recent_emoji_cache.dart`
- `lib/src/ui/messages/widgets/emoji_picker.dart`
