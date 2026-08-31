import 'dart:typed_data';

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
