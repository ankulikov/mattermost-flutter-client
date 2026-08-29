import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';

final class DioMattermostApi implements MattermostApi {
  DioMattermostApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<MattermostUserDto> getCurrentUser() async {
    final Response<Object?> response = await _get('/users/me');
    return MattermostUserDto.fromJson(_object(response.data));
  }

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() async {
    final Response<Object?> response = await _get('/users/me/teams');
    return _dtoList(response.data, MattermostTeamDto.fromJson);
  }

  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) async {
    final Response<Object?> response = await _get(
      '/users/$userId/teams/$teamId/channels',
      options: Options(headers: _conditionalHeaders(etag)),
    );
    return _dtoList(response.data, MattermostChannelDto.fromJson);
  }

  @override
  Future<MattermostChannelCategoriesDto> getChannelCategories({
    required String userId,
    required String teamId,
  }) async {
    final Response<Object?> response = await _get(
      '/users/$userId/teams/$teamId/channels/categories',
    );
    return MattermostChannelCategoriesDto.fromJson(_object(response.data));
  }

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return const <MattermostUserDto>[];
    final Response<Object?> response = await _post(
      '/users/ids',
      data: jsonEncode(userIds),
    );
    return _dtoList(response.data, MattermostUserDto.fromJson);
  }

  @override
  Future<MattermostUserDto> getUserById(String userId) async {
    final Response<Object?> response = await _get('/users/$userId');
    return MattermostUserDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostUserStatusDto> getUserStatus(String userId) async {
    final Response<Object?> response = await _get('/users/$userId/status');
    return MattermostUserStatusDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostImageDto> getUserProfileImage({
    required String userId,
    int lastPictureUpdate = 0,
  }) async {
    final Response<List<int>> response = await _withCancellation(
      (CancelToken? cancelToken) => _dio.get<List<int>>(
        '/users/$userId/image',
        queryParameters: <String, Object?>{
          if (lastPictureUpdate > 0) '_': lastPictureUpdate,
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: const <String, String>{'Accept': 'image/*'},
        ),
        cancelToken: cancelToken,
      ),
    );
    final List<int>? data = response.data;
    if (data == null) {
      throw const FormatException('Expected a binary image response');
    }
    return MattermostImageDto(
      bytes: data is Uint8List ? data : Uint8List.fromList(data),
      contentType: response.headers.value(Headers.contentTypeHeader),
    );
  }

  @override
  Future<MattermostEmojiDto> getCustomEmojiByName(String name) async {
    final Response<Object?> response = await _get(
      '/emoji/name/${Uri.encodeComponent(name)}',
    );
    return MattermostEmojiDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostImageDto> getCustomEmojiImage(String emojiId) async {
    final Response<List<int>> response = await _withCancellation(
      (CancelToken? cancelToken) => _dio.get<List<int>>(
        '/emoji/${Uri.encodeComponent(emojiId)}/image',
        options: Options(
          responseType: ResponseType.bytes,
          headers: const <String, String>{'Accept': 'image/*'},
        ),
        cancelToken: cancelToken,
      ),
    );
    final List<int>? data = response.data;
    if (data == null) {
      throw const FormatException('Expected a binary image response');
    }
    return MattermostImageDto(
      bytes: data is Uint8List ? data : Uint8List.fromList(data),
      contentType: response.headers.value(Headers.contentTypeHeader),
    );
  }

  @override
  Future<MattermostFileContentDto> getFile(String fileId) =>
      _getFileContent('/files/${Uri.encodeComponent(fileId)}');

  @override
  Future<MattermostFileContentDto> getFileThumbnail(String fileId) =>
      _getFileContent('/files/${Uri.encodeComponent(fileId)}/thumbnail');

  @override
  Future<MattermostFileContentDto> getFilePreview(String fileId) =>
      _getFileContent('/files/${Uri.encodeComponent(fileId)}/preview');

  Future<MattermostFileContentDto> _getFileContent(String path) async {
    final Response<List<int>> response = await _withCancellation(
      (CancelToken? cancelToken) => _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
      ),
    );
    final List<int>? data = response.data;
    if (data == null) {
      throw const FormatException('Expected a binary file response');
    }
    return MattermostFileContentDto(
      bytes: data is Uint8List ? data : Uint8List.fromList(data),
      contentType: response.headers.value(Headers.contentTypeHeader),
    );
  }

  @override
  Future<MattermostGroupChannelUsersDto> getUsersForGroupChannels(
    List<String> channelIds,
  ) async {
    if (channelIds.isEmpty) {
      return const MattermostGroupChannelUsersDto(
        usersByChannelId: <String, List<MattermostUserDto>>{},
      );
    }
    final Response<Object?> response = await _post(
      '/users/group_channels',
      data: jsonEncode(channelIds),
    );
    final Map<String, Object?> body = _object(response.data);
    return MattermostGroupChannelUsersDto(
      usersByChannelId: Map<String, List<MattermostUserDto>>.unmodifiable(
        body.map(
          (String channelId, Object? users) =>
              MapEntry<String, List<MattermostUserDto>>(
                channelId,
                _dtoList(users, MattermostUserDto.fromJson),
              ),
        ),
      ),
    );
  }

  @override
  Future<MattermostChannelDto> createDirectChannel({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final Response<Object?> response = await _post(
      '/channels/direct',
      data: jsonEncode(<String>[currentUserId, otherUserId]),
    );
    return MattermostChannelDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) async {
    final Response<Object?> response = await _get(
      '/channels/$channelId/posts',
      queryParameters: <String, Object?>{'page': page, 'per_page': perPage},
      options: Options(headers: _conditionalHeaders(etag)),
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostListDto> getPostsBefore({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) async {
    final Response<Object?> response = await _get(
      '/channels/$channelId/posts',
      queryParameters: <String, Object?>{
        'before': postId,
        'page': page,
        'per_page': perPage,
      },
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostListDto> getPostsSince({
    required String channelId,
    required int since,
  }) async {
    final Response<Object?> response = await _get(
      '/channels/$channelId/posts',
      queryParameters: <String, Object?>{'since': since},
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostDto> createPost(
    MattermostCreatePostRequestDto post,
  ) async {
    final Response<Object?> response = await _post(
      '/posts',
      data: post.toJson(),
    );
    return MattermostPostDto.fromJson(_object(response.data));
  }

  @override
  Future<void> saveReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) async {
    await _post(
      '/reactions',
      data: <String, Object?>{
        'user_id': userId,
        'post_id': postId,
        'emoji_name': emojiName,
      },
    );
  }

  @override
  Future<void> deleteReaction({
    required String userId,
    required String postId,
    required String emojiName,
  }) async {
    await _delete(
      '/users/${Uri.encodeComponent(userId)}'
      '/posts/${Uri.encodeComponent(postId)}'
      '/reactions/${Uri.encodeComponent(emojiName)}',
    );
  }

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) async {
    final Response<Object?> response = await _get(
      '/posts/$rootPostId/thread',
      queryParameters: <String, Object?>{
        'perPage': perPage,
        'direction': direction.name,
        if (fromPost case final String value) 'fromPost': value,
        if (fromCreateAt case final int value) 'fromCreateAt': value,
      },
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostUserThreadsDto> getUserThreads({
    required String userId,
    required String teamId,
    int perPage = 60,
    String? before,
    bool extended = true,
    bool unread = false,
  }) async {
    final Response<Object?> response = await _get(
      '/users/$userId/teams/$teamId/threads',
      queryParameters: <String, Object?>{
        'per_page': perPage,
        'extended': extended,
        if (before case final String value) 'before': value,
        if (unread) 'unread': true,
      },
    );
    return MattermostUserThreadsDto.fromJson(_object(response.data));
  }

  @override
  Future<void> updateThreadRead({
    required String userId,
    required String teamId,
    required String threadId,
    required int timestamp,
  }) async {
    await _put(
      '/users/$userId/teams/$teamId/threads/$threadId/read/$timestamp',
    );
  }

  static Map<String, String>? _conditionalHeaders(String? etag) =>
      etag == null ? null : <String, String>{'If-None-Match': etag};

  Future<Response<Object?>> _get(
    String path, {
    Map<String, Object?>? queryParameters,
    Options? options,
  }) => _withCancellation(
    (CancelToken? cancelToken) => _dio.get<Object?>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    ),
  );

  Future<Response<Object?>> _post(String path, {Object? data}) =>
      _withCancellation(
        (CancelToken? cancelToken) =>
            _dio.post<Object?>(path, data: data, cancelToken: cancelToken),
      );

  Future<Response<Object?>> _put(String path, {Object? data}) =>
      _withCancellation(
        (CancelToken? cancelToken) =>
            _dio.put<Object?>(path, data: data, cancelToken: cancelToken),
      );

  Future<Response<Object?>> _delete(String path) => _withCancellation(
    (CancelToken? cancelToken) =>
        _dio.delete<Object?>(path, cancelToken: cancelToken),
  );

  Future<Response<T>> _withCancellation<T>(
    Future<Response<T>> Function(CancelToken? cancelToken) request,
  ) async {
    final RequestCancellation? cancellation = RequestCancellation.current;
    if (cancellation == null) return request(null);
    final CancelToken token = CancelToken();
    final void Function() detach = cancellation.addListener(token.cancel);
    try {
      return await request(token);
    } finally {
      detach();
    }
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const FormatException('Expected a JSON object');
  }

  static List<T> _dtoList<T>(Object? value, T Function(JsonMap) decode) {
    if (value is! List<Object?>) {
      throw const FormatException('Expected a JSON array');
    }
    return List<T>.unmodifiable(
      value.map((Object? item) {
        if (item is! JsonMap) {
          throw const FormatException('Expected a JSON object in array');
        }
        return decode(item);
      }),
    );
  }
}
