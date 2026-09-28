# Mattermost Flutter

A cross-platform Mattermost client for Android, iOS, Web, macOS, and Windows.
It keeps the interface responsive while server data loads, adapts the workspace
to the available width, and gives message-heavy teams a faster way to handle
their day.

## What sets it apart

### One Inbox for work that needs attention

The official Mattermost client does not provide this Inbox. It collects
mentions, direct messages, integration messages, and unread followed threads in
one place. New items stay separate from messages you have postponed, so the
Inbox works as a lightweight communication queue rather than another unread
badge.

### A responsive interface from the first frame

The client does not wait for every request before it becomes useful. Initial
loads have clear retry states, while refresh and pagination keep existing
content on screen. Layouts respond to the space they receive: compact windows
use stacked screens, medium widths add a navigation rail, and expanded windows
show channels, messages, and threads side by side.

### Markdown that is comfortable to write

The message composer includes formatting controls and a live Markdown preview.
It styles completed Markdown while preserving the exact source text, selection,
clipboard behavior, and IME composing range. Messages support the Mattermost
dialect, including tables, task lists, code highlighting, LaTeX, channel links,
mentions, and custom emoji.

### Status changes without the settings hunt

The profile page puts availability and custom status controls together. Common
statuses such as "In a meeting", "Out for lunch", "Commuting", and "On
vacation" take one tap, with expiration handled through the Mattermost API.

## More of the client

- Network-first channels, posts, threads, search, and sidebar data
- Post permalinks that open the right channel or thread without losing the
  source screen's scroll position or draft
- Direct and group messages grouped by conversation and sender in the Inbox
- Reactions, custom emoji search, recent emoji, and mention autocomplete
- User cards, authenticated avatars, file previews, and legacy interactive
  message attachments
- Keyboard navigation, scalable text, semantics, touch and pointer workflows,
  and light and dark themes
- Secure token storage and redacted diagnostics

## Documentation

- [Architecture and module index](docs/features/readme.md)
- [Release builds](docs/RELEASES.md)
- [Instructions for coding agents](AGENTS.md)

## Run the project

Install a stable Flutter SDK compatible with the constraint in `pubspec.yaml`,
then run:

```sh
flutter pub get
flutter pub run build_runner build
dart run tool/generate_mattermost_system_emojis.dart
flutter run
```

Useful checks during development:

```sh
dart format --output=none --set-exit-if-changed lib test tool
dart analyze
flutter analyze
flutter test
```

Platform toolchains still apply: iOS and macOS builds require macOS and Xcode,
while Windows builds require Windows. Android release signing and CI release
artifacts are covered in [the release guide](docs/RELEASES.md).
