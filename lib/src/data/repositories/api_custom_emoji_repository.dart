import 'dart:collection';
import 'dart:typed_data';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/cache/custom_emoji_cache.dart';
import 'package:mattermost_flutter/src/data/database/recent_emoji_cache.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/domain/repositories/emoji_repository.dart';

final class ApiCustomEmojiRepository implements CustomEmojiRepository {
  ApiCustomEmojiRepository({
    required MattermostApi api,
    required CustomEmojiCache cache,
    required RecentEmojiCache recentCache,
  }) : _api = api,
       _cache = cache,
       _recentCache = recentCache;

  final MattermostApi _api;
  final CustomEmojiCache _cache;
  final RecentEmojiCache _recentCache;
  final Map<String, Future<CustomEmojiContent>> _inFlight =
      <String, Future<CustomEmojiContent>>{};
  final Map<String, Future<List<CustomEmojiReference>>> _metadataInFlight =
      <String, Future<List<CustomEmojiReference>>>{};
  final LinkedHashMap<String, _MetadataCacheEntry> _metadataQueries =
      LinkedHashMap<String, _MetadataCacheEntry>();
  final Map<String, CustomEmojiReference> _metadataByName =
      <String, CustomEmojiReference>{};

  static const Duration _metadataTtl = Duration(minutes: 5);
  static const int _maximumMetadataQueries = 50;

  @override
  Future<List<CustomEmojiReference>> getPage({
    required String accountId,
    int page = 0,
    int perPage = 90,
  }) => _loadMetadata(
    key: '$accountId|page:$page|perPage:$perPage',
    request: () => _api.getCustomEmojis(page: page, perPage: perPage),
  );

  @override
  Future<List<CustomEmojiReference>> search({
    required String accountId,
    required String term,
  }) {
    final String normalized = term.trim().toLowerCase();
    if (normalized.isEmpty) {
      return Future<List<CustomEmojiReference>>.value(
        const <CustomEmojiReference>[],
      );
    }
    return _loadMetadata(
      key: '$accountId|search:$normalized',
      request: () => _api.searchCustomEmojis(normalized),
    );
  }

  Future<List<CustomEmojiReference>> _loadMetadata({
    required String key,
    required Future<List<MattermostEmojiDto>> Function() request,
  }) async {
    final DateTime now = DateTime.now();
    final _MetadataCacheEntry? cached = _metadataQueries.remove(key);
    if (cached != null && now.difference(cached.loadedAt) < _metadataTtl) {
      _metadataQueries[key] = cached;
      return cached.emojis;
    }
    final Future<List<CustomEmojiReference>>? existing = _metadataInFlight[key];
    if (existing != null) return existing;

    final Future<List<CustomEmojiReference>> operation = request().then((
      List<MattermostEmojiDto> values,
    ) {
      final List<CustomEmojiReference> emojis = values
          .where(
            (MattermostEmojiDto emoji) =>
                emoji.id.isNotEmpty &&
                emoji.name.isNotEmpty &&
                emoji.deleteAt == 0,
          )
          .map(_referenceFromDto)
          .toList(growable: false);
      for (final CustomEmojiReference emoji in emojis) {
        _metadataByName[emoji.name.toLowerCase()] = emoji;
      }
      _metadataQueries[key] = _MetadataCacheEntry(
        loadedAt: DateTime.now(),
        emojis: List<CustomEmojiReference>.unmodifiable(emojis),
      );
      while (_metadataQueries.length > _maximumMetadataQueries) {
        _metadataQueries.remove(_metadataQueries.keys.first);
      }
      return emojis;
    });
    _metadataInFlight[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_metadataInFlight[key], operation)) {
        _metadataInFlight.remove(key);
      }
    }
  }

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
      final CustomEmojiReference? known = _metadataByName[name];
      if (known != null) {
        resolvedId = known.id;
        resolvedUpdate = known.updatedAt;
      } else {
        final MattermostEmojiDto metadata = await _api.getCustomEmojiByName(
          name,
        );
        final CustomEmojiReference reference = _referenceFromDto(metadata);
        _metadataByName[name] = reference;
        resolvedId = reference.id;
        resolvedUpdate = reference.updatedAt;
      }
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

  @override
  Future<List<String>> getRecent({required String accountId}) =>
      _recentCache.read(accountId);

  @override
  Future<void> rememberRecent({
    required String accountId,
    required String emojiName,
  }) => _recentCache.remember(accountId: accountId, emojiName: emojiName);
}

CustomEmojiReference _referenceFromDto(MattermostEmojiDto emoji) =>
    CustomEmojiReference(
      name: emoji.name,
      id: emoji.id,
      updatedAt: emoji.updateAt,
    );

final class _MetadataCacheEntry {
  const _MetadataCacheEntry({required this.loadedAt, required this.emojis});

  final DateTime loadedAt;
  final List<CustomEmojiReference> emojis;
}
