import 'dart:convert';
import 'dart:io';

const String _pinnedEmojiJsonUrl =
    'https://raw.githubusercontent.com/mattermost/mattermost/'
    '35242cbed7bf3e379801312b9077acc8edffcd78/'
    'webapp/channels/src/utils/emoji.json';
const String _defaultOutputPath =
    'lib/src/domain/models/mattermost_system_emojis.g.dart';
final RegExp _shortcodePattern = RegExp(r'^[a-z0-9_+-]+$');

/// Generates the Mattermost system-shortcode dictionary used at runtime.
///
/// The input is Mattermost's `emoji.json`. It is deliberately fetched or read
/// only by this development tool; JSON files are never included in the Flutter
/// asset bundle. To regenerate from a downloaded file, run:
///
/// ```sh
/// dart run tool/generate_mattermost_system_emojis.dart --input /path/emoji.json
/// ```
Future<void> main(List<String> arguments) async {
  final String? inputPath = _optionValue(arguments, '--input');
  final String outputPath =
      _optionValue(arguments, '--output') ?? _defaultOutputPath;
  _validateArguments(arguments);

  final String contents = inputPath == null
      ? await _download(_pinnedEmojiJsonUrl)
      : await File(inputPath).readAsString();
  final _EmojiCatalog emojis = _parseEmojiJson(contents);
  final File output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(_render(emojis));
  stdout.writeln(
    'Generated ${emojis.aliases.length} system emoji aliases and '
    '${emojis.entries.length} catalog entries at $outputPath',
  );
}

String? _optionValue(List<String> arguments, String name) {
  final int index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 == arguments.length || arguments[index + 1].startsWith('--')) {
    throw ArgumentError('$name requires a value');
  }
  return arguments[index + 1];
}

void _validateArguments(List<String> arguments) {
  const Set<String> options = <String>{'--input', '--output'};
  for (int index = 0; index < arguments.length; index += 1) {
    final String argument = arguments[index];
    if (!options.contains(argument)) {
      throw ArgumentError('Unknown argument: $argument');
    }
    index += 1;
  }
}

Future<String> _download(String url) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Could not download emoji.json: ${response.statusCode}',
      );
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

_EmojiCatalog _parseEmojiJson(String contents) {
  final Object? decoded = jsonDecode(contents);
  if (decoded is! List<Object?>) {
    throw const FormatException('emoji.json must contain a JSON array');
  }

  final Map<String, String> aliases = <String, String>{};
  final List<_EmojiEntry> entries = <_EmojiEntry>[];
  for (final Object? item in decoded) {
    if (item is! Map<Object?, Object?>) {
      throw const FormatException('emoji.json entries must be objects');
    }
    final String category = item['category'] as String? ?? '';
    final String unified = item['unified'] as String? ?? '';
    if (category == 'custom' || unified.isEmpty) continue;

    final String emoji = _unicodeFromUnified(unified);
    final Set<String> names = <String>{
      if (item['short_name'] case final String shortName) shortName,
      for (final Object? name
          in (item['short_names'] as List<Object?>? ?? const <Object?>[]))
        if (name is String) name,
    };
    if (names.isEmpty) continue;
    final String name = item['short_name'] as String? ?? names.first;
    for (final String name in names) {
      if (!_shortcodePattern.hasMatch(name)) {
        throw FormatException('Unsupported emoji shortcode: $name');
      }
      final String? previous = aliases[name];
      if (previous != null && previous != emoji) {
        throw FormatException('Conflicting emoji shortcode: $name');
      }
      aliases[name] = emoji;
    }
    entries.add(
      _EmojiEntry(
        name: name,
        unicode: emoji,
        category: category,
        aliases: List<String>.unmodifiable(names),
      ),
    );
  }
  if (aliases.isEmpty) {
    throw const FormatException(
      'emoji.json did not contain system emoji aliases',
    );
  }
  return _EmojiCatalog(
    aliases: Map<String, String>.unmodifiable(aliases),
    entries: List<_EmojiEntry>.unmodifiable(entries),
  );
}

String _unicodeFromUnified(String unified) => String.fromCharCodes(
  unified.split('-').map((String codePoint) => int.parse(codePoint, radix: 16)),
);

String _render(_EmojiCatalog emojis) {
  final List<MapEntry<String, String>> aliases = emojis.aliases.entries.toList()
    ..sort(
      (MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key),
    );
  final StringBuffer output = StringBuffer(
    '''// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Generated from Mattermost's emoji.json at:
// $_pinnedEmojiJsonUrl
// Run: dart run tool/generate_mattermost_system_emojis.dart

import 'package:mattermost_flutter/src/domain/models/emoji.dart';

/// Mattermost system emoji shortcodes mapped to their Unicode text.
const Map<String, String> mattermostSystemEmojis = <String, String>{
  // dart format off
''',
  );
  for (final MapEntry<String, String> entry in aliases) {
    output.writeln("  '${entry.key}': '${entry.value}',");
  }
  output.writeln('  // dart format on');
  output.writeln('};');
  output.writeln();
  output.writeln(
    '/// Canonical system emoji entries in Mattermost category order.',
  );
  output.writeln(
    'const List<SystemEmojiDefinition> mattermostSystemEmojiCatalog = '
    '<SystemEmojiDefinition>[',
  );
  output.writeln('  // dart format off');
  for (final _EmojiEntry entry in emojis.entries) {
    final String aliases = entry.aliases
        .map((String value) => "'$value'")
        .join(', ');
    output.writeln(
      "  SystemEmojiDefinition(name: '${entry.name}', unicode: "
      "'${entry.unicode}', category: '${entry.category}', aliases: "
      "<String>[$aliases]),",
    );
  }
  output.writeln('  // dart format on');
  output.writeln('];');
  return output.toString();
}

final class _EmojiCatalog {
  const _EmojiCatalog({required this.aliases, required this.entries});

  final Map<String, String> aliases;
  final List<_EmojiEntry> entries;
}

final class _EmojiEntry {
  const _EmojiEntry({
    required this.name,
    required this.unicode,
    required this.category,
    required this.aliases,
  });

  final String name;
  final String unicode;
  final String category;
  final List<String> aliases;
}
