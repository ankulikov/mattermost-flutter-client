import 'dart:typed_data';

/// One built-in Mattermost emoji and the aliases accepted by the server.
final class SystemEmojiDefinition {
  const SystemEmojiDefinition({
    required this.name,
    required this.unicode,
    required this.category,
    required this.aliases,
  });

  /// Canonical shortcode shown by the picker and sent to the reactions API.
  final String name;
  final String unicode;
  final String category;
  final List<String> aliases;
}

/// Metadata embedded by Mattermost in posts that reference a custom emoji.
final class CustomEmojiReference {
  const CustomEmojiReference({
    required this.name,
    this.id = '',
    this.updatedAt = 0,
  });

  final String name;
  final String id;
  final int updatedAt;

  @override
  bool operator ==(Object other) =>
      other is CustomEmojiReference &&
      other.name == name &&
      other.id == id &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(name, id, updatedAt);
}

/// Binary custom-emoji payload, kept independent from Flutter image decoding.
final class CustomEmojiContent {
  const CustomEmojiContent({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}
