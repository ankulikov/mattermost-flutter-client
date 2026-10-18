# Android app updates

The update feature discovers stable releases from the public GitHub Releases
API and can install a compatible APK over the current Android application. The
first updater-enabled build must still be installed manually. macOS, iOS, Web,
and Windows do not use this installer.

## Architecture and ownership

The vertical slice lives under `lib/src/features/updates/`:

- `domain` owns semantic/build version comparison, compatible ABI selection,
  update state, and the repository contract;
- `data` owns the unauthenticated GitHub adapter, installed-package metadata,
  verified temporary download, and the Android platform gateway;
- `presentation` owns the Riverpod controller and adaptive update screen.

The GitHub client is process-wide infrastructure configured separately from
`MattermostApi`. It never receives a Mattermost token, cookie, message, or user
identifier. Release metadata is held in memory only. ETags avoid downloading an
unchanged page again during the process lifetime.

## Discovery and release identity

The client requests stable, non-draft releases in pages of 100 and continues
until GitHub reports that there is no next page. A ten-page safety bound avoids
unbounded work. A later-page failure keeps the releases already fetched but
marks the history incomplete; installation stays disabled until a complete
retry succeeds.

Tags must be `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH+BUILD`. Semantic
versions are compared first. The optional tag build distinguishes releases
with the same semantic version. The installed build number comes from platform
package metadata, not `pubspec.yaml`. Flutter's release workflow adds an ABI
offset to split-APK version codes (1,000 for ARM32, 2,000 for ARM64, and 4,000
for x86-64); discovery removes the running process ABI's offset before comparing
the tag build. The native installer still compares the unmodified Android
version codes.

Android assets must use the release workflow's ABI suffixes:

```text
mattermost-vVERSION-arm64-v8a.apk
mattermost-vVERSION-armeabi-v7a.apk
mattermost-vVERSION-x86_64.apk
```

The GitHub asset must provide a `sha256:` digest and an HTTPS download URL on
`github.com`. Selection follows Android's ordered `SUPPORTED_ABIS` list. Every
newer release is shown oldest-to-newest, while the install action targets the
newest release that has a compatible asset.

## Download and installation safety

The APK is downloaded into the application cache with one active operation at
a time. The client verifies the exact byte count and computes SHA-256 on a
background isolate before calling Android. Partial and staged files are removed
after failure or after the native installer has copied the APK into its session.

The Kotlin gateway accepts only APKs inside the application cache. Before it
creates a `PackageInstaller.Session`, it verifies:

- the archive package name matches the running application ID;
- the archive version code is strictly greater than the installed version code;
- the archive's current signing certificate set exactly matches the installed
  application's signing certificate set.

The session asks Android for `USER_ACTION_NOT_REQUIRED` where supported, but the
client always handles `STATUS_PENDING_USER_ACTION` and opens the system-owned
confirmation UI. Android 8 and newer also require the user to trust this app as
an install source. The update screen links to that per-source setting and checks
the permission again when the app resumes.

Install status is delivered to a small transparent `InstallResultActivity`
through the `PackageInstaller` session's Activity `PendingIntent`. It opens the
system confirmation UI when required. After a successful replacement, it opens
`MainActivity` and posts an “Update installed — Open Mattermost” notification
as a fallback. `MainActivity` removes the fallback once it reaches the resumed
state. On Android 13 and newer, the fallback is shown only when the user has
allowed app notifications. Auto-open begins with the first published version
that contains `InstallResultActivity`; replacing the app with an older APK that
lacks the callback activity still completes the update but cannot auto-open it.

Successful replacement preserves application data because the application ID
and signing identity do not change. The updater never uninstalls the current
application as a recovery path.

## UI and refresh behavior

The Profile settings list opens the update screen. It shows installed and
available versions, all intervening release notes as selectable GitHub Flavored
Markdown, download progress, permission guidance, retry, and “Later.” Headings,
lists, emphasis, code, and link labels are formatted. URLs for this repository's
pull requests and version comparisons use compact `#123` and
`vA...vB` labels. HTTP(S) links open in the external browser. Images are
rendered as their alternative text, and raw HTML is not rendered.

The application performs a quiet, non-blocking check after launch for the
active account, at most once per day across process restarts. The timestamp is
stored in the account-scoped `user_preferences.last_check_update` column. A
successful discovery with a compatible update opens a modal showing the
installed and available versions. “Update now” opens the update screen; “Later”
postpones the next automatic check for one day. Opening the update screen
manually always checks immediately and records the attempt without consulting
the automatic-check timestamp. An initial failure shows retry; a refresh
failure preserves existing release information.

The screen uses the shared 700 px compact breakpoint, constrains expanded
content width, scrolls at large text scales, and exposes progress semantics.

## Verification

Unit tests cover version/build ordering, ABI selection, pagination,
prerelease filtering, partial history, asset validation, cleanup, controller
retry/refresh/install states, the persisted one-day bound, compact and expanded
layouts, large text, permission recovery, and install blocking for partial
history.

An end-to-end release test still requires two APKs signed by the production
release key. Install the older APK, sign in and change a preference, then update
to the newer APK and verify that both session and preference survive.
