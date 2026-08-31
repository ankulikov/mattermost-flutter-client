import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/cache/custom_emoji_cache.dart';
import 'package:mattermost_flutter/src/data/repositories/api_custom_emoji_repository.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';

void main() {
  test(
    'coalesces image loads and reuses the account-scoped name cache',
    () async {
      final _EmojiApi api = _EmojiApi();
      final _MemoryEmojiCache cache = _MemoryEmojiCache();
      final ApiCustomEmojiRepository repository = ApiCustomEmojiRepository(
        api: api,
        cache: cache,
      );

      final Future<CustomEmojiContent> first = repository.getByName(
        accountId: 'server|user:ada',
        name: 'Party_Parrot',
        emojiId: 'emoji-1',
        updatedAt: 42,
      );
      final Future<CustomEmojiContent> second = repository.getByName(
        accountId: 'server|user:ada',
        name: 'party_parrot',
        emojiId: 'emoji-1',
        updatedAt: 42,
      );

      await api.started.future;
      expect(api.imageCalls, 1);
      expect(api.metadataCalls, 0);
      api.complete();
      final List<CustomEmojiContent> loaded = await Future.wait(
        <Future<CustomEmojiContent>>[first, second],
      );
      expect(loaded.first.bytes, <int>[1, 2, 3]);

      final CustomEmojiContent cached = await repository.getByName(
        accountId: 'server|user:ada',
        name: 'party_parrot',
        emojiId: 'emoji-1',
        updatedAt: 42,
      );
      expect(cached.bytes, <int>[1, 2, 3]);
      expect(api.imageCalls, 1);
      expect(
        cache.lastWrittenKey,
        'server|user:ada|emoji:party_parrot|id:emoji-1|updated:42',
      );
    },
  );

  test('resolves metadata by name when post metadata is unavailable', () async {
    final _EmojiApi api = _EmojiApi()..complete();
    final ApiCustomEmojiRepository repository = ApiCustomEmojiRepository(
      api: api,
      cache: _MemoryEmojiCache(),
    );

    await repository.getByName(
      accountId: 'server|user:ada',
      name: 'party_parrot',
    );

    expect(api.metadataCalls, 1);
    expect(api.requestedName, 'party_parrot');
    expect(api.requestedImageId, 'emoji-1');
  });
}

final class _MemoryEmojiCache implements CustomEmojiCache {
  final Map<String, Uint8List> values = <String, Uint8List>{};
  String? lastWrittenKey;

  @override
  Future<Uint8List?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write({
    required String key,
    required Uint8List bytes,
    required String? contentType,
  }) async {
    lastWrittenKey = key;
    values[key] = bytes;
  }
}

final class _EmojiApi extends Fake implements MattermostApi {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int metadataCalls = 0;
  int imageCalls = 0;
  String? requestedName;
  String? requestedImageId;

  void complete() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<MattermostEmojiDto> getCustomEmojiByName(String name) async {
    metadataCalls += 1;
    requestedName = name;
    return const MattermostEmojiDto(
      id: 'emoji-1',
      creatorId: 'ada',
      name: 'party_parrot',
      createAt: 1,
      updateAt: 42,
      deleteAt: 0,
    );
  }

  @override
  Future<MattermostImageDto> getCustomEmojiImage(String emojiId) async {
    imageCalls += 1;
    requestedImageId = emojiId;
    if (!started.isCompleted) started.complete();
    await _release.future;
    return MattermostImageDto(
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      contentType: 'image/png',
    );
  }
}
