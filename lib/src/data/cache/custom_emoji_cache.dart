import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

abstract interface class CustomEmojiCache {
  Future<Uint8List?> read(String key);

  Future<void> write({
    required String key,
    required Uint8List bytes,
    required String? contentType,
  });

  Future<void> remove(String key);
}

/// Temporary account-scoped cache for custom emoji image content.
final class FlutterCustomEmojiCache implements CustomEmojiCache {
  factory FlutterCustomEmojiCache() => instance;

  FlutterCustomEmojiCache._()
    : _cacheManager = CacheManager(
        Config(
          'mattermost_custom_emoji',
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 5000,
        ),
      );

  static final FlutterCustomEmojiCache instance = FlutterCustomEmojiCache._();

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
  }) => _cacheManager.putFile(
    key,
    bytes,
    key: key,
    maxAge: const Duration(days: 365),
    fileExtension: _fileExtension(contentType),
  );

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
