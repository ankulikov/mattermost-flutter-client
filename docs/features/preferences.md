# User preferences

User preferences are durable, account-owned settings that affect the local
client experience. They survive process restarts so an authenticated account
returns to its selected display theme without a server request.

## Ownership and storage

`UserPreferencesRepository` is the only application-facing persistence
contract. Its Drift implementation reads and replaces the preferences for the
active session's durable account scope ID. Presentation and app composition
code do not query the database directly.

The `user_preferences` table contains one row per account/server scope. The row
stores the complete preferences document as JSON in `preferences_json` and the
last app-update check attempt in the nullable `last_check_update` column.
Tokens, message content, and other server data are never included. Updating a
known preference preserves unknown JSON fields so an older client does not
erase settings written by a newer client.

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
- `lib/src/data/database/app_database.dart`
