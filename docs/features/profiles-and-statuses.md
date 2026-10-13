# Profiles and statuses

User profiles appear in message cards, the channel sidebar, profile cards, and
the current-user profile page. Profile data and image bytes have separate
freshness rules.

## Profile cache and avatars

`UserRepository` owns the account-scoped profile cache. Profiles live for seven
days and are keyed by account/server ID. The cache includes the fields needed by
the full profile card and the server's image version.

For users, the avatar version comes from `last_picture_update`; bot accounts use
`bot_last_icon_update`. Authenticated image requests use
`GET /users/{user_id}/image?_=<version>` through `MattermostApi`.

Image bytes live in a temporary `flutter_cache_manager` cache. Its key includes
the account, user ID, and version, so all visible copies share one object and an
avatar update creates a new key. Native and desktop builds use temporary files;
Web uses session memory. The cache is limited to 500 objects.

The UI draws colored initials immediately. After bytes arrive, Flutter decodes
them to the control's target size off the build path. A load or decode failure
keeps the initials.

## Current-user profile

The profile page requests `GET /users/me` and
`GET /users/{user_id}/status` in parallel. Availability updates use
`PUT /users/{user_id}/status`. Do Not Disturb asks for an expiration and sends
`dnd_end_time` in Unix seconds. Away and Offline do not ask for a duration
because Mattermost does not auto-expire them.

Quick custom statuses provide one-tap choices for "In a meeting", "Out for
lunch", "Commuting", and "Day off". Set and clear use `PUT` and `DELETE`
on `/users/{user_id}/status/custom`. Mattermost has no separate read endpoint;
the mapper reads `user.props.customStatus` and ignores malformed or expired
values.

Profile mutations preserve the current profile while they run and report a
non-blocking error on failure. Current-user profile state is not stored in
Drift, so each page entry or process restart begins with a new server snapshot.

## Relevant code

- `lib/src/features/profile/`
- `lib/src/data/repositories/mattermost_user_repository.dart`
- `lib/src/data/database/user_profile_cache_dao.dart`
- `lib/src/ui/users/`
