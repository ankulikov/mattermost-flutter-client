# User profiles and avatars

User details requested by ID are cached independently in Drift. The
`cached_user_profiles` table contains an account/server scope (server URL plus
the signed-in user ID), requested user ID, first name, last name, username,
nickname, position, email, profile-image update timestamp, and expiration
timestamp. Reads are DB-first; missing or expired IDs are fetched
together with `POST /users/ids` and upserted with a seven-day TTL. Expired values
are not served when refresh fails.

This profile cache does not store avatar bytes. Its picture-update timestamp is
passed to the avatar repository and participates in the versioned avatar key.

Clicking a message author name or avatar opens an auto-disposed profile card.
The card combines a fresh, cache-bypassing `GET /users/{user_id}` lookup with a
live `GET /users/{user_id}/status` request and exposes explicit loading, retry,
and direct-message action states. The batch cache remains an optimization for
author and dialog-name resolution only. The direct-message action is
implemented by the channels domain contract and `POST /channels/direct`, not by
the widget.

User profile responses do not contain an image URL. They expose
`last_picture_update`; bot accounts expose `is_bot` and
`bot_last_icon_update`. Profile image bytes come from authenticated
`GET /api/v4/users/{user_id}/image`. The optional `_` query value is ignored by
the server and carries the relevant update timestamp for cache busting.

Message authors retain that image version in domain state. The avatar
repository is the only owner of image loading and caching: it checks a
`flutter_cache_manager` entry, calls `MattermostApi` on a miss, and coalesces
concurrent misses. Cache keys are the complete versioned endpoint URL, which
scopes them by server/account, user, and update timestamp. Entries are temporary,
bounded, and contain no credentials.

Presentation watches an auto-disposed provider. Initials remain visible while
bytes are read or downloaded and on all failures; valid bytes are decoded and
resized by Flutter only after the asynchronous load completes. The same provider
key, repository in-flight map, file cache, and Flutter image cache prevent a
second network request when another visible message has the same author.

The cache-manager dependency is used instead of issuing image HTTP requests
from a widget. This preserves the `MattermostApi` authentication boundary and
works on Android, iOS, macOS, Windows, and Web (session-memory caching on Web).

See the official [user endpoint specification](https://github.com/mattermost/mattermost/blob/master/api/v4/source/users.yaml).
