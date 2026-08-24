# Mattermost Flutter

Cross-platform, offline-first Mattermost client for Android, iOS, Web, macOS,
and Windows.

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
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Replace `com.example.mattermost` with the final reverse-DNS application id before
shipping. Windows builds require Windows, iOS/macOS builds require macOS and
Xcode.

When Drift persistence is implemented, copy the matching `sqlite3.wasm` and
`drift_worker.js` artifacts to `web/`. Their versions must match the resolved
`sqlite3` and `drift` packages; do not commit arbitrary binaries from the web.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Agent and contributor rules](AGENTS.md)

## Useful commands

```sh
flutter run -d chrome
flutter run -d macos
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed lib test
dart run build_runner watch --delete-conflicting-outputs
```

