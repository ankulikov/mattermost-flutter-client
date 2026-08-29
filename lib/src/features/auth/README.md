# Mattermost session authentication

The authentication flow accepts a normalized Mattermost server URL and a
transient Mattermost session token obtained through the SSO browser flow. The
repository validates the token with `GET /api/v4/users/me` before persisting it.
Credentials are stored only in platform secure storage; they are never written
to the application database or kept in presentation state.

`MattermostAuthRepository` is intentionally independent of the token source:
SSO and any legacy migration use the same validate → save → activate sequence.
The storage key migrated from the former PAT key to a neutral session-token key;
the legacy key is read once and migrated without dropping a working session.

Native SSO uses `flutter_inappwebview` on Android, iOS, macOS, and Windows.
`SsoBrowserGateway` admits a token only from the native Cookie Manager after a
top-level return to the selected Mattermost origin and path. It clears only
`MMAUTHTOKEN`, `MMUSERID`, and `MMCSRF` for that server before and after each
attempt; it never uses JavaScript to read cookies. The WebView deliberately uses
the platform default cookie store: Apple non-persistent WebViews are invisible
to this plugin's Cookie Manager, while its Android incognito implementation
clears the global cookie store. Flutter Web returns an explicit
browser-unavailable outcome because cross-origin HttpOnly cookies cannot be read
safely there.

Debug builds emit structured authentication diagnostics under the
`MattermostAuth` logger. Browser navigations contain only scheme, host, path,
query-key names, and policy decisions; query values, fragments, cookie values,
session tokens, exception messages, and IdP page contents are never logged.
Attempt ids correlate WebView navigation, cookie polling, cleanup, and the
terminal typed browser result; subsequent API validation remains visible in the
sanitized `MattermostHttp` log.

The auth data layer owns one closeable `MattermostApi` for the active session.
Restoring a session reads secure storage once and validates it before activation;
only a confirmed `401`/`403` (or corrupt partial credentials) clears storage.
Network failures, timeouts, rate limits and server errors preserve credentials
for a later retry. Feature repositories receive the already authenticated API
from `app/di` and never read the token. Signing out or switching servers closes
the previous Dio transport and its connection pool.

The current implementation supports one active account. A future multi-account
implementation should store non-secret account metadata in Drift and address
secure-storage entries by account id.
