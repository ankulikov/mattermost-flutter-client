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

GitHub's release-asset metadata must expose the SHA-256 digest for every Android
APK. The Android in-app updater rejects an asset with a missing digest, an
unexpected filename/ABI, a non-GitHub download URL, or a mismatched size/hash.
Do not rename Android assets without updating the rules in
`docs/features/updates.md` and the update client together. Release publishing
also rejects an empty generated release-notes body because the client presents
every intervening stable release.

## Android signing secrets

The Android release job fails unless these repository or environment secrets are
present:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded JKS or PKCS#12 release keystore;
- `ANDROID_KEY_ALIAS`: alias of the release key;
- `ANDROID_KEY_PASSWORD`: password for that key;
- `ANDROID_KEYSTORE_PASSWORD`: password for the keystore.

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
- The ad-hoc macOS build uses the legacy file-based Keychain rather than the
  Data Protection Keychain, whose access-group entitlement needs an authorized
  provisioning profile. Restore the Data Protection Keychain when macOS
  distribution signing is configured.
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

## Local Android release signing

`flutter run --release` and `flutter build apk --release` require a signed APK.
The release Gradle configuration reads `android/key.properties`; Git ignores
that file and the keystore. Keep a secure backup of both the keystore and its
passwords. Android updates must use the same signing certificate as the
installed application.

The first updater-enabled release must be installed manually. Later direct APK
installs require Android's “install unknown apps” trust for Mattermost, and the
OS may still require confirmation. Never resolve an identity or signing mismatch
by uninstalling the current app because that erases its local session and data.

Create a keystore once:

```sh
keytool -genkeypair -v \
  -keystore mm-flutter-key.jks \
  -alias mattermost-release \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Create `android/key.properties` with the selected passwords:

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=mattermost-release
storeFile=../mm-flutter-key.jks
```

`storeFile` is resolved relative to `android/app`. The example places the
keystore in `android`; an absolute path also works.

Build and verify the APK:

```sh
flutter clean
flutter pub get
flutter build apk --release
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

The verifier must confirm the APK signature schemes and print the signing
certificate. If `apksigner` is absent from `PATH`, use the executable from the
Android SDK's `build-tools/<version>/` directory.

## iOS launch assets

Replace the images in `ios/Runner/Assets.xcassets/LaunchImage.imageset/` to
customize the launch screen. The same assets can be changed in Xcode by opening
`ios/Runner.xcworkspace`, selecting `Runner/Assets.xcassets` in the Project
Navigator, and dropping in the replacement images.
