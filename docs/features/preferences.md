# User preferences

App preferences are durable, process-wide settings that affect the local client
experience. They survive process restarts and are available before session
restoration, so the first frame uses the selected display theme.

## Ownership and storage

`AppSettingsRepository` is the application-facing persistence contract.
Its `SharedPreferencesAsync` implementation stores process-wide values under
namespaced keys. Presentation code does not query platform storage directly.

The current keys are `mattermost.app.theme` and
`mattermost.app.last_update_check_utc_ms`. The latter is a UTC epoch timestamp.
Tokens, message content, profiles, and other server data are never included.
The legacy account-scoped Drift `user_preferences` table remains for one
compatibility release; new reads and writes do not use it.

## JSON compatibility

The current document has one field:

```json
{"theme":"light"}
```

Supported theme values are `light` and `dark`. A missing row, malformed JSON,
a non-object document, or a missing, non-string, or unknown `theme` value falls
back to `light`. Readers ignore unknown fields. This keeps reads compatible as
new preferences and theme choices are introduced.

## Relevant code

- `lib/src/features/preferences/domain/`
- `lib/src/features/preferences/data/`
- `lib/src/features/preferences/data/repositories/shared_preferences_app_preferences_repository.dart`
