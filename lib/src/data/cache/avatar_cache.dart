import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

abstract interface class UserAvatarCache {
  Future<Uint8List?> read(String key);

  Future<void> write({
    required String key,
    required Uint8List bytes,
    required String? contentType,
  });

  Future<void> remove(String key);
}

/// Temporary, size-bounded cache for versioned profile images.
///
/// Cache keys contain the account/server URL, user id, and picture update time,
/// so tenant data and successive avatar versions never alias each other.
final class FlutterUserAvatarCache implements UserAvatarCache {
  factory FlutterUserAvatarCache() => instance;

  FlutterUserAvatarCache._()
    : _cacheManager = CacheManager(
        Config(
          'mattermost_user_avatars',
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 500,
        ),
      );

  static final FlutterUserAvatarCache instance = FlutterUserAvatarCache._();

  final BaseCacheManager _cacheManager;

  @override
  Future<Uint8List?> read(String key) async {
    final FileInfo? cached = await _cacheManager.getFileFromCache(key);
    if (cached == null) return null;
    try {
      return await cached.file.readAsBytes();
    } on Object {
      await _cacheManager.removeFile(key);
      return null;
    }
  }

  @override
  Future<void> write({
    required String key,
    required Uint8List bytes,
    required String? contentType,
  }) async {
    await _cacheManager.putFile(
      key,
      bytes,
      key: key,
      maxAge: const Duration(days: 365),
      fileExtension: _fileExtension(contentType),
    );
  }

  @override
  Future<void> remove(String key) => _cacheManager.removeFile(key);
}

String _fileExtension(String? contentType) {
  final String mediaType =
      contentType?.split(';').first.trim().toLowerCase() ?? '';
  return switch (mediaType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'img',
  };
}
