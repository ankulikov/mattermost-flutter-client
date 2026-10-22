# Authentication and sessions

Authentication owns server discovery, credentials, the active API client, and
the lifetime of the realtime connection.

## Server addresses

The sign-in form accepts full `http://` or `https://` origins as well as a
schemeless host (with an optional deployment path). Schemeless addresses always
try HTTPS first, then fall back to HTTP only for explicitly allowed local hosts.
Explicit HTTP is rejected for other hosts. HTTP is allowed for `localhost`,
`.lan` and `.local` domains, plus IPv4 private (`10/8`, `172.16/12`,
`192.168/16`), loopback (`127/8`), link-local (`169.254/16`), CGNAT
(`100.64/10`), and IPv6 unique-local (`fc00::/7`) addresses. The origin that
responds successfully becomes the session origin for API, SSO, and realtime
traffic.

## Sign-in methods

Before showing password controls, the client requests `/config/client`. Email
and username login are available only when the server enables them. A password
is sent only to `POST /users/login`; the session token returned in the response
headers enters the same validation and storage flow as a personal access token
or an SSO token.

Interactive SSO is exposed to the UI through the domain-level
`SsoBrowserGateway`. Native adapters accept only `MMAUTHTOKEN` read by the
platform cookie manager after the browser returns to the selected Mattermost
origin. The UI never receives cookies. Before and after an attempt, the adapter
clears only `MMAUTHTOKEN`, `MMUSERID`, and `MMCSRF` for that server.

Flutter Web reports embedded SSO as unavailable because browser JavaScript
cannot read cross-origin HttpOnly cookies. The client does not work around that
boundary.

## Session lifetime

The authentication repository owns the only closable `MattermostApi` for the
active account. It reads secure storage once while restoring a session or uses
the credential supplied by the current sign-in attempt. Feature repositories
receive the authenticated API and cannot access the token.

Application startup begins in a distinct restoring state. The sign-in surface
is not rendered until secure storage and server-side session validation have
resolved. A saved token is accepted only after `GET /users/me` succeeds; an
expired token is cleared, while a network failure preserves the credential and
offers retry. After a session is accepted, the authenticated shell remains
behind the startup surface until the account-scoped theme preference is loaded,
so neither the sign-in UI nor a default-themed shell flashes during startup.

An authenticated session also owns one `SessionRealtimeService` and one
`WebSocketGateway`. Opening a channel, Inbox item, or thread never creates an
extra WebSocket connection.

Logout first attempts `POST /users/logout`. It removes the local token and
closes the API client even when that request fails, so a network outage cannot
leave the account signed in locally.

On macOS, credentials use the file-based Keychain. An item created under an
older app signing identity can remain readable but reject deletion with
`errSecInvalidOwnerEdit` (`-25244`). Credential cleanup then asks the system
`security` utility to delete only the affected Mattermost key and verifies that
the plugin can no longer read it. If the item remains, logout reports a storage
failure instead of claiming that the credential was removed.

## Security rules

- Tokens belong only in `flutter_secure_storage`.
- Cookies, authorization headers, message bodies, and personal data are absent
  from diagnostics.
- Server changes close the old API client and its connection pool.
- SSO accepts credentials only from the selected Mattermost origin.
- Certificate pinning, custom certificate authorities, database encryption,
  telemetry, and authentication persistence changes require explicit review.

## Relevant code

- `lib/src/data/repositories/mattermost_auth_repository.dart`
- `lib/src/data/api/mattermost_server_discovery.dart`
- `lib/src/data/platform/in_app_webview_sso_browser_gateway.dart`
- `lib/src/data/realtime/session_realtime_service.dart`
- `lib/src/ui/auth/`
