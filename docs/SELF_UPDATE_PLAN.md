# Self-update implementation plan

Research date: 2026-10-17. This document is a plan; it does not describe an implemented feature.

## Goal and scope

Deliver updates from [GitHub Releases](https://github.com/ankulikov/mattermost-flutter-client/releases) inside the application, with Android and macOS as the first supported platforms. Show the changes in every stable release newer than the installed version, install the newest compatible build, and preserve credentials and settings across replacement. iOS and Windows can remain informational or unsupported until their distribution paths are ready.

Existing installations do not contain an updater. Users will need to install the first updater-enabled release manually once; later releases can use the in-app flow.

## Recommendation

Use **Sparkle 2 for macOS** and an **Android `PackageInstaller` session through a small Kotlin bridge**. Implement GitHub Releases discovery, release history, download status, and the update screen in Flutter. Keep the existing Android APKs and macOS DMG: [Sparkle supports DMG updates](https://sparkle-project.org/documentation/), so a ZIP is not required.

“Consent only once” has platform limits:

- **Android:** The user's permission to install from this app can persist. Eligible self-updates can request installation without another confirmation, but Android can still return `STATUS_PENDING_USER_ACTION`. The app must show the system confirmation when requested. See [`PackageInstaller.SessionParams`](https://developer.android.com/reference/android/content/pm/PackageInstaller.SessionParams) and [`canRequestPackageInstalls()`](https://developer.android.com/reference/kotlin/android/content/pm/PackageManager).
- **macOS:** Sparkle can remember the user's automatic-update preference and install updates on quit when possible. macOS may still request authorization if the app's location is not writable. See [Sparkle update settings](https://sparkle-project.org/documentation/customization/) and [authorization behavior](https://sparkle-project.org/documentation/custom-user-interfaces/).

Do not promise an unconditional one-time-consent flow on either platform.

## Library and framework assessment

| Option | Decision | Reason |
| --- | --- | --- |
| [`package_info_plus`](https://pub.dev/packages/package_info_plus) | Use | Reads the installed version and build number on Android and macOS. Check its Flutter minimum when selecting a version. |
| [Sparkle 2](https://sparkle-project.org/documentation/) | Use on macOS | Provides signed archive verification, download, app replacement, relaunch, and update preferences. Integrate through Swift in `Runner` and expose the required controls to Flutter. |
| [`auto_updater`](https://pub.dev/packages/auto_updater) | Do not select yet | Wraps Sparkle, but its documented macOS troubleshooting path disables the sandbox. This app currently enables the sandbox; [Sparkle documents a supported sandbox integration](https://sparkle-project.org/documentation/sandboxing/). Reconsider only after proving that integration with this wrapper. |
| [`desktop_updater`](https://pub.dev/packages/desktop_updater) | Alternative | Supports desktop updates and DMGs, but introduces its own signed feed, helper, and release workflow. Sparkle is the narrower macOS choice here. |
| [`apk_sideload`](https://pub.dev/packages/apk_sideload) | Fallback only | Launches the standard Android APK installer. It does not provide the desired path for minimizing confirmation on later updates. |

The current [release workflow](../.github/workflows/release.yml) publishes three ABI-specific, release-signed Android APKs and an ARM64 macOS DMG. The [release guide](RELEASES.md) states that the Mac app is ad-hoc signed and not notarized. Before promising smooth Mac updates on users' machines, move to Developer ID signing, hardened runtime, and notarization. Apple's [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution/) require Developer ID signing; the current ad-hoc signature is not a production signing identity.

## Release discovery and presentation

1. Read the installed version **and build number** from the package. Release builds override the `0.1.0+1` value in [`pubspec.yaml`](../pubspec.yaml) through CI, so that file alone cannot identify a shipped build.
2. Query the public [GitHub Releases API](https://docs.github.com/en/rest/releases/releases) with `GET /repos/ankulikov/mattermost-flutter-client/releases?per_page=100`. Exclude drafts and, for the initial stable channel, prereleases. Parse tags and compare versions and build numbers. Do not use `/releases/latest` as a numeric-version comparison: GitHub's latest-release selection depends on release metadata.
3. Paginate until the set of releases newer than the installed version is complete. Do not assume API order matches semantic-version order. If retrieval stops early, show an explicit partial/error state rather than claiming to show every intervening release.
4. Display every intervening release's title and body, oldest to newest, in one “What's new” view. Render GitHub-provided text defensively. Offer one install action for the newest compatible release. Reject an empty or unusable release body during publishing.
5. Select an Android asset matching the device ABI, or a supported macOS ARM64 asset. Reject missing, ambiguous, or incompatible assets. Show download progress and retry; verify size and SHA-256 before handing the file to the installer. Clean up failed downloads.
6. Check at an appropriate launch/resume interval and provide “Check for updates” in settings. Cache only small update metadata, use `ETag`, and back off on `403`/`429` using GitHub's rate-limit headers. Unauthenticated requests to public resources share a [60-request-per-hour limit per originating IP](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api); follow [GitHub's retry guidance](https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api).

GitHub is a separate update source. Keep its HTTP adapter in the update feature's data layer; `MattermostApi` remains the boundary for Mattermost REST traffic. Do not send a Mattermost token to GitHub or include it in update diagnostics.

For macOS, generate an **Ed25519-signed Sparkle appcast** during release publishing, with the DMG as its enclosure. A stable feed can be an `appcast.xml` asset reached through GitHub's [`releases/latest/download/...` URL](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases). CI must verify that the URL resolves to the newly published release before declaring success. Sparkle uses the appcast for installation; the Flutter screen uses the Releases API to show the combined intervening history. See the [Sparkle publishing guide](https://sparkle-project.org/documentation/publishing/).

## Implementation tasks

- [ ] **Define release identity rules.** Preserve the Android application ID, macOS bundle ID, and Android release signing key. Require strictly increasing Android version codes and macOS `CFBundleVersion` values, including patch releases. Android requires a matching application ID and signing identity for an in-place update; uninstalling to recover from a mismatch erases app data. See [Android update rules](https://developer.android.com/google/play/app-updates).
- [ ] **Add an `updates` vertical slice.** Put version comparison, release selection, and update states in `domain`; GitHub parsing, download verification, and platform gateways in `data`; and the controller and screen in `presentation`. Keep UI code away from direct HTTP, filesystem, and installer calls.
- [ ] **Build the shared update UI.** Show installed and available versions, all intervening notes, progress, retry, “Later,” and actionable failures. Cover compact and expanded widths, large text, keyboard focus, semantics, and localized strings.
- [ ] **Implement Android installation.** Add the necessary install permissions and a Kotlin `PackageInstaller.Session` gateway. Check `canRequestPackageInstalls()` and direct the user to the per-source system setting when needed. On supported self-updates request `USER_ACTION_NOT_REQUIRED`; handle `STATUS_PENDING_USER_ACTION` through the system confirmation flow. Validate the APK's package, version, and signing identity before installation.
- [ ] **Implement macOS installation.** Integrate a current Sparkle 2 release through Swift Package Manager. Keep the sandbox and configure its installer XPC service and entitlements as documented. Add the public update-signing key and feed URL to the app. Enable automatic checking and expose a user preference for automatic installation. Test replacement from `/Applications` and from a nonwritable location.
- [ ] **Upgrade macOS release signing.** Sign the app and Sparkle helpers with Developer ID, enable hardened runtime, notarize and staple, verify Gatekeeper acceptance, then produce and Sparkle-sign the DMG. Keep DMG distribution for first installation.
- [ ] **Update CI publishing gates.** Verify asset names, checksums, signatures, monotonic build numbers, appcast resolution, and release-note presence. Publish the appcast only after its referenced artifact is available.
- [ ] **Prove data continuity.** Update in place with an active session and changed preferences on both platforms. On macOS, test Keychain access during the move from ad-hoc to Developer ID signing: [`secure_credential_store.dart`](../lib/src/data/storage/secure_credential_store.dart) uses the legacy file-based Keychain, and the [authentication notes](features/authentication.md) document signing-identity ownership problems. Any authentication-persistence change requires the explicit review specified in `AGENTS.md`.
- [ ] **Document and verify.** Update architecture and release notes. Format changed Dart files, run `flutter analyze`, focused tests, and the full suite for this cross-cutting change. Test UI on both sides of relevant breakpoints and at large text scale.

## Testing without public releases

1. Use fixture GitHub responses to test version ordering, multiple intervening releases, pagination, prereleases, missing assets, checksum failures, and rate limits.
2. In test builds only, point the update clients at a local server serving a Sparkle appcast and matching signed DMGs, plus Android release metadata and signed APKs. Keep local endpoint and cleartext-network exceptions out of production configuration.
3. Build two test versions with increasing build numbers and unchanged platform identities. Install the older version, sign in, change settings, and update to the newer version. Verify that the session and settings remain available without another login.
4. Exercise interrupted downloads, bad hashes/signatures, declined permissions, OS-requested confirmation, nonwritable macOS install locations, and recovery after restart.
5. Finish with one private or prerelease end-to-end test against the actual GitHub asset layout before enabling production checks.

As of the research date, [Android's developer-verification FAQ](https://developer.android.com/developer-verification/guides/faq) says direct sideloading is outside the initial September 2026 participating-store enforcement, with broader rollout planned later. Recheck that policy before launch in additional regions.
