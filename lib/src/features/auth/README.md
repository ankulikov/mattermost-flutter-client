# Personal access token authentication

The MVP authentication flow accepts a Mattermost server URL and a personal
access token (PAT). The repository validates the credentials with
`GET /api/v4/users/me` before persisting them. Credentials are stored only in
platform secure storage; they are never written to the application database or
kept in presentation state.

The current implementation supports one active account. A future multi-account
implementation should store non-secret account metadata in Drift and address
secure-storage entries by account id.

