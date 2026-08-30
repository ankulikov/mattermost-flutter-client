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
- [Target layered architecture and migration plan](docs/TARGET_ARCHITECTURE.md)
- [Agent and contributor rules](AGENTS.md)

## Useful commands

```sh
flutter run -d chrome
flutter run -d macos
flutter test
dart run tool/check_import_boundaries.dart
flutter analyze
dart format --output=none --set-exit-if-changed lib test tool
flutter pub run build_runner watch
```
