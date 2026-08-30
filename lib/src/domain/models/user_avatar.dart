import 'dart:typed_data';

/// Decoded-independent profile image payload owned by the users feature.
final class UserAvatar {
  const UserAvatar({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
}
