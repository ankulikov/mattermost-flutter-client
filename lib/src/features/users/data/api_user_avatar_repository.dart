import 'dart:typed_data';

import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/users/data/user_avatar_cache.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_avatar.dart';
import 'package:mattermost_flutter/src/features/users/domain/user_avatar_repository.dart';

final class ApiUserAvatarRepository implements UserAvatarRepository {
  ApiUserAvatarRepository({
    required MattermostApi api,
    required UserAvatarCache cache,
  }) : _api = api,
       _cache = cache;

  final MattermostApi _api;
  final UserAvatarCache _cache;
  final Map<String, Future<UserAvatar>> _inFlight =
      <String, Future<UserAvatar>>{};

  @override
  Future<UserAvatar> getAvatar({
    required String accountId,
    required String userId,
    required int profileImageUpdatedAt,
  }) async {
    final String key = _profileImageUri(
      accountId: accountId,
      userId: userId,
      profileImageUpdatedAt: profileImageUpdatedAt,
    ).toString();
    final Future<UserAvatar>? existing = _inFlight[key];
    if (existing != null) return existing;

    final Future<UserAvatar> request = _load(
      key: key,
      userId: userId,
      profileImageUpdatedAt: profileImageUpdatedAt,
    );
    _inFlight[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    }
  }

  Future<UserAvatar> _load({
    required String key,
    required String userId,
    required int profileImageUpdatedAt,
  }) async {
    Uint8List? cached;
    try {
      cached = await _cache.read(key);
    } on Object {
      // Cache availability is an optimization; the API remains authoritative.
    }
    if (cached != null && cached.isNotEmpty) {
      return UserAvatar(bytes: cached, contentType: null);
    }

    final MattermostImageDto response = await _api.getUserProfileImage(
      userId: userId,
      lastPictureUpdate: profileImageUpdatedAt,
    );
    if (response.bytes.isEmpty) {
      throw const FormatException('Profile image response was empty');
    }
    try {
      await _cache.write(
        key: key,
        bytes: response.bytes,
        contentType: response.contentType,
      );
    } on Object {
      // A temporary cache failure must not hide an image already downloaded.
    }
    return UserAvatar(bytes: response.bytes, contentType: response.contentType);
  }
}

Uri _profileImageUri({
  required String accountId,
  required String userId,
  required int profileImageUpdatedAt,
}) {
  final Uri serverUrl = Uri.parse(
    accountId.endsWith('/') ? accountId : '$accountId/',
  );
  return serverUrl
      .resolve('api/v4/users/$userId/image')
      .replace(
        queryParameters: profileImageUpdatedAt > 0
            ? <String, String>{'_': '$profileImageUpdatedAt'}
            : null,
      );
}
