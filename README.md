# Mattermost Flutter

Cross-platform, network-first Mattermost client for Android, iOS, Web, macOS,
and Windows. Channel navigation, posts, threads, and paging state are kept in
memory so opening a channel always starts with current server data.

The repository contains the application skeleton and architecture baseline. The
host environment used to create it did not contain Flutter SDK, so generated
platform runners are intentionally produced locally rather than committed as
handwritten approximations.

## Bootstrap

Install a stable Flutter SDK with Dart 3.8 or newer, then run from the repository
root:

```sh
flutter config --enable-web --enable-macos-desktop --enable-windows-desktop
flutter create \
  --project-name mattermost_flutter \
  --org com.example.mattermost \
  --platforms android,ios,web,macos,windows \
  .
flutter pub get
flutter pub run build_runner build
dart run tool/generate_mattermost_system_emojis.dart
flutter analyze
flutter test
```

Replace `com.example.mattermost` with the final reverse-DNS application id before
shipping. Windows builds require Windows, iOS/macOS builds require macOS and
Xcode.

Drift remains available for future durable feature data such as user profiles.
Its current schema intentionally has no feature tables. Web database artifacts,
when needed, must match the resolved `sqlite3` and `drift` package versions.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Agent and contributor rules](AGENTS.md)

## Useful commands

```sh
flutter run -d chrome
flutter run -d macos
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed lib test tool
dart run tool/generate_mattermost_system_emojis.dart
flutter pub run build_runner watch
```

## Android release signing for local builds

`flutter run --release` and `flutter build apk --release` require a signed APK.
The release Gradle configuration reads signing settings from
`android/key.properties`; this file and the keystore are intentionally ignored
by Git.

Create a keystore once and keep a secure backup of it and its passwords. Do not
replace it after distributing an APK: Android updates must be signed with the
same certificate.

```sh
keytool -genkeypair -v \
  -keystore mm-flutter-key.jks \
  -alias mattermost-release \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Create `android/key.properties` with the passwords chosen by `keytool`:

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=mattermost-release
storeFile=../mm-flutter-key.jks
```

`storeFile` is resolved relative to the `android/app` directory. The example
assumes that `mm-flutter-key.jks` is in the `android` directory. An absolute path
is also supported.

Build and verify a local release APK:

```sh
flutter clean
flutter pub get
flutter build apk --release
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

The verification command must report that APK signature schemes are verified
and print the signing certificate. If `apksigner` is not on `PATH`, run the
copy from your Android SDK's `build-tools/<version>/` directory.
