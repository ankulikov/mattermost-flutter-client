# GitHub release builds

Pushing a semantic version tag starts `.github/workflows/release.yml`:

```text
vMAJOR.MINOR.PATCH
vMAJOR.MINOR.PATCH+BUILD
```

The semantic version becomes the application build name. If the optional numeric
`BUILD` suffix is absent, the GitHub Actions run number becomes the application
build number. Example:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The workflow publishes these files directly as assets of the corresponding
GitHub Release, so users download the file itself rather than a workflow-artifact
ZIP:

- three ABI-specific, release-signed Android APKs;
- an unsigned Windows x64 ZIP without PDB files;
- an ARM64-only macOS DMG with an ad-hoc-signed app bundle;
- an unsigned iOS IPA.

Each platform also has a uniquely named SHA-256 checksum file. Matching Dart and
native symbol files remain private workflow artifacts for 90 days. Keep them for
as long as the corresponding binary can produce crash reports.

## Android signing secrets

The Android release job fails unless these repository or environment secrets are
present:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded JKS or PKCS#12 release keystore;
- `ANDROID_KEY_ALIAS` — alias of the release key;
- `ANDROID_KEY_PASSWORD` — password for that key;
- `ANDROID_KEYSTORE_PASSWORD` — password for the keystore.

The job reconstructs the key only on the ephemeral runner, verifies the APK
signature, and removes the temporary files before it exits. Install the APK that
matches the device ABI: `arm64-v8a` for almost all current phones/tablets,
`armeabi-v7a` for older 32-bit ARM devices, and `x86_64` mainly for emulators.

## Signing limitations

These outputs are build verification artifacts, not store-ready packages:

- Android APKs in the GitHub Release are signed with the configured release key.
  The same signing key must be retained for future updates to install over an
  existing copy of the app.
- Windows can run unsigned executables, but SmartScreen can warn or block them.
- The macOS app uses only Xcode's certificate-free ad-hoc signature required for
  a coherent application bundle. The DMG has no Developer ID signature and is
  not notarized, so Gatekeeper can block it on another Mac.
- The iOS IPA cannot be installed on devices or uploaded to App Store Connect
  until it is signed with a certificate and provisioning profile.

## CI and caches

Format checking, static analysis, and the complete Flutter test suite run once in
the `verify` job. Platform builds start only after it succeeds and do not repeat
tests. Normal branch CI does not run for tags, avoiding a second test invocation.

Flutter SDK caches remain separated by operating system and CPU architecture.
The source portion of the Pub cache is keyed by the pinned Flutter version and
`pubspec.lock`, uses GitHub's cross-OS cache format, and is populated by `verify`
before the build jobs start. The two Apple builds share one ARM64 runner and one
CocoaPods cache. Gradle uses its own cache and wrapper validation.

The workflow pins Flutter to `3.47.2` and pins every third-party action to a full
commit SHA. Update the CI and release workflow version together when upgrading
Flutter.
