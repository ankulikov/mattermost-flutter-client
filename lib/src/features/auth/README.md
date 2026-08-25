# Personal access token authentication

The MVP authentication flow accepts a Mattermost server URL and a personal
access token (PAT). The repository validates the credentials with
`GET /api/v4/users/me` before persisting them. Credentials are stored only in
platform secure storage; they are never written to the application database or
kept in presentation state.

The auth data layer owns one closeable `MattermostApi` for the active session.
Restoring a session reads secure storage once; feature repositories receive the
already authenticated API from `app/di` and never read the token. Signing out or
switching servers closes the previous Dio transport and its connection pool.

The current implementation supports one active account. A future multi-account
implementation should store non-secret account metadata in Drift and address
secure-storage entries by account id.
