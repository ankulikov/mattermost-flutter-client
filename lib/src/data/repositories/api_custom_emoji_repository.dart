import 'dart:typed_data';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/cache/custom_emoji_cache.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';

final class ApiCustomEmojiRepository implements CustomEmojiRepository {
  ApiCustomEmojiRepository({
    required MattermostApi api,
    required CustomEmojiCache cache,
  }) : _api = api,
       _cache = cache;

  final MattermostApi _api;
  final CustomEmojiCache _cache;
  final Map<String, Future<CustomEmojiContent>> _inFlight =
      <String, Future<CustomEmojiContent>>{};

  @override
  Future<CustomEmojiContent> getByName({
    required String accountId,
    required String name,
    String emojiId = '',
    int updatedAt = 0,
  }) async {
    final String normalizedName = name.toLowerCase();
    final String requestKey = '$accountId|emoji:$normalizedName';
    final Future<CustomEmojiContent>? existing = _inFlight[requestKey];
    if (existing != null) return existing;

    final Future<CustomEmojiContent> request = _load(
      accountId: accountId,
      name: normalizedName,
      emojiId: emojiId,
      updatedAt: updatedAt,
    );
    _inFlight[requestKey] = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight[requestKey], request)) {
        _inFlight.remove(requestKey);
      }
    }
  }

  Future<CustomEmojiContent> _load({
    required String accountId,
    required String name,
    required String emojiId,
    required int updatedAt,
  }) async {
    String resolvedId = emojiId;
    int resolvedUpdate = updatedAt;
    if (resolvedId.isEmpty) {
      final MattermostEmojiDto metadata = await _api.getCustomEmojiByName(name);
      resolvedId = metadata.id;
      resolvedUpdate = metadata.updateAt;
    }
    if (resolvedId.isEmpty) {
      throw const FormatException(
        'Custom emoji response did not contain an id',
      );
    }

    final String cacheKey =
        '$accountId|emoji:$name|id:$resolvedId|updated:$resolvedUpdate';
    Uint8List? cached;
    try {
      cached = await _cache.read(cacheKey);
    } on Object {
      // Cache availability is an optimization; the API remains authoritative.
    }
    if (cached != null && cached.isNotEmpty) {
      return CustomEmojiContent(bytes: cached);
    }

    final MattermostImageDto response = await _api.getCustomEmojiImage(
      resolvedId,
    );
    if (response.bytes.isEmpty) {
      throw const FormatException('Custom emoji image response was empty');
    }
    try {
      await _cache.write(
        key: cacheKey,
        bytes: response.bytes,
        contentType: response.contentType,
      );
    } on Object {
      // A cache failure must not hide content already downloaded.
    }
    return CustomEmojiContent(
      bytes: response.bytes,
      contentType: response.contentType,
    );
  }
}
