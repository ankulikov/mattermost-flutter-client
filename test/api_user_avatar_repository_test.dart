import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/core/api/dio_mattermost_api.dart';
import 'package:mattermost_flutter/src/features/users/data/api_user_avatar_repository.dart';
import 'package:mattermost_flutter/src/features/users/data/user_avatar_cache.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_avatar.dart';

void main() {
  test(
    'deduplicates concurrent requests and reuses the versioned cache',
    () async {
      final _ImageAdapter adapter = _ImageAdapter();
      final Dio dio = Dio(
        BaseOptions(baseUrl: 'https://chat.example.com/api/v4'),
      )..httpClientAdapter = adapter;
      final _MemoryAvatarCache cache = _MemoryAvatarCache();
      final ApiUserAvatarRepository repository = ApiUserAvatarRepository(
        api: DioMattermostApi(dio: dio),
        cache: cache,
      );

      final Future<UserAvatar> first = repository.getAvatar(
        accountId: 'https://chat.example.com',
        userId: 'user-1',
        profileImageUpdatedAt: 42,
      );
      final Future<UserAvatar> second = repository.getAvatar(
        accountId: 'https://chat.example.com',
        userId: 'user-1',
        profileImageUpdatedAt: 42,
      );
      await adapter.started.future;
      expect(adapter.calls, 1);
      adapter.complete();

      final List<UserAvatar> loaded = await Future.wait(<Future<UserAvatar>>[
        first,
        second,
      ]);
      expect(loaded[0].bytes, <int>[1, 2, 3]);
      expect(loaded[1].bytes, <int>[1, 2, 3]);

      final UserAvatar cached = await repository.getAvatar(
        accountId: 'https://chat.example.com',
        userId: 'user-1',
        profileImageUpdatedAt: 42,
      );
      expect(cached.bytes, <int>[1, 2, 3]);
      expect(adapter.calls, 1);
      expect(cache.lastWrittenKey, contains('/users/user-1/image?_=42'));
    },
  );
}

final class _MemoryAvatarCache implements UserAvatarCache {
  final Map<String, Uint8List> values = <String, Uint8List>{};
  String? lastWrittenKey;

  @override
  Future<Uint8List?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

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

final class _ImageAdapter implements HttpClientAdapter {
  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int calls = 0;

  void complete() => _release.complete();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    if (!started.isCompleted) started.complete();
    await _release.future;
    return ResponseBody.fromBytes(
      <int>[1, 2, 3],
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['image/png'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
