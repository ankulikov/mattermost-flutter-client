import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/async/request_cancellation.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';

final class DioMattermostApi
    implements MattermostProfileApi, MattermostSessionApi {
  DioMattermostApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<MattermostUserDto> getCurrentUser() async {
    final Response<Object?> response = await _get('/users/me');
    return MattermostUserDto.fromJson(_object(response.data));
  }

  @override
  Future<void> logout() => _post('/users/logout');

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
  Future<MattermostChannelDto> getChannel(String channelId) async {
    final Response<Object?> response = await _get(
      '/channels/${Uri.encodeComponent(channelId)}',
    );
    return MattermostChannelDto.fromJson(_object(response.data));
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
  Future<List<MattermostChannelMemberDto>> getChannelMembersForUser({
    required String userId,
    required String teamId,
  }) async {
    final Response<Object?> response = await _get(
      '/users/${Uri.encodeComponent(userId)}'
      '/teams/${Uri.encodeComponent(teamId)}/channels/members',
    );
    return _dtoList(response.data, MattermostChannelMemberDto.fromJson);
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
  Future<List<MattermostUserDto>> getUsersByUsernames(
    List<String> usernames,
  ) async {
    if (usernames.isEmpty) return const <MattermostUserDto>[];
    final Response<Object?> response = await _post(
      '/users/usernames',
      data: jsonEncode(usernames),
    );
    return _dtoList(response.data, MattermostUserDto.fromJson);
  }

  @override
  Future<List<MattermostUserDto>> searchUsers({
    required String term,
    required int limit,
  }) async {
    final Response<Object?> response = await _post(
      '/users/search',
      data: <String, Object?>{
        'term': term,
        'allow_inactive': false,
        'limit': limit,
      },
    );
    return _dtoList(response.data, MattermostUserDto.fromJson);
  }

  @override
  Future<List<MattermostChannelDto>> searchChannels({
    required String term,
    required int limit,
  }) async {
    final Response<Object?> response = await _post(
      '/channels/search',
      queryParameters: const <String, Object?>{'system_console': true},
      data: <String, Object?>{
        'term': term,
        'page': 0,
        'per_page': limit,
        'exclude_default_channels': false,
      },
    );
    final Object? data = response.data;
    if (data is List<Object?>) {
      return _dtoList(data, MattermostChannelDto.fromJson);
    }
    final Map<String, Object?> body = _object(data);
    return _dtoList(body['channels'], MattermostChannelDto.fromJson);
  }

  @override
  Future<MattermostUserAutocompleteDto> autocompleteUsers({
    required String teamId,
    required String channelId,
    required String name,
    required int limit,
  }) async {
    final Response<Object?> response = await _get(
      '/users/autocomplete',
      queryParameters: <String, Object?>{
        'in_team': teamId,
        'in_channel': channelId,
        'name': name,
        'limit': limit,
      },
    );
    return MattermostUserAutocompleteDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostSearchDto> searchPosts({
    required String teamId,
    required MattermostPostSearchRequestDto request,
  }) async {
    final Response<Object?> response = await _post(
      '/teams/${Uri.encodeComponent(teamId)}/posts/search',
      data: request.toJson(),
    );
    return MattermostPostSearchDto.fromJson(_object(response.data));
  }

  @override
  Future<List<MattermostChannelDto>> autocompleteChannelsForSearch({
    required String teamId,
    required String name,
  }) async {
    final Response<Object?> response = await _get(
      '/teams/${Uri.encodeComponent(teamId)}/channels/autocomplete',
      queryParameters: <String, Object?>{'name': name},
    );
    return _dtoList(response.data, MattermostChannelDto.fromJson);
  }

  @override
  Future<List<MattermostGroupDto>> searchMentionGroups({
    required String name,
    required int limit,
  }) async {
    final Response<Object?> response = await _get(
      '/groups',
      queryParameters: <String, Object?>{
        'q': name,
        'filter_allow_reference': true,
        'page': 0,
        'per_page': limit,
        'include_member_count': true,
      },
    );
    return _dtoList(response.data, MattermostGroupDto.fromJson);
  }

  @override
  Future<List<MattermostGroupDto>> getGroupsByNames(List<String> names) async {
    if (names.isEmpty) return const <MattermostGroupDto>[];
    final Response<Object?> response = await _post(
      '/groups/names',
      data: jsonEncode(names),
    );
    return _dtoList(response.data, MattermostGroupDto.fromJson);
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
  Future<MattermostUserStatusDto> updateUserStatus({
    required String userId,
    required String status,
    required int dndEndTime,
  }) async {
    final String encodedUserId = Uri.encodeComponent(userId);
    final Response<Object?> response = await _put(
      '/users/$encodedUserId/status',
      data: <String, Object?>{
        'user_id': userId,
        'status': status,
        'dnd_end_time': dndEndTime,
      },
    );
    return MattermostUserStatusDto.fromJson(_object(response.data));
  }

  @override
  Future<void> updateUserCustomStatus({
    required String userId,
    required MattermostCustomStatusRequestDto status,
  }) => _put(
    '/users/${Uri.encodeComponent(userId)}/status/custom',
    data: status.toJson(),
  );

  @override
  Future<void> removeUserCustomStatus(String userId) =>
      _delete('/users/${Uri.encodeComponent(userId)}/status/custom');

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
  Future<List<MattermostEmojiDto>> getCustomEmojis({
    int page = 0,
    int perPage = 90,
  }) async {
    final Response<Object?> response = await _get(
      '/emoji',
      queryParameters: <String, Object?>{
        'page': page,
        'per_page': perPage,
        'sort': 'name',
      },
    );
    return _dtoList(response.data, MattermostEmojiDto.fromJson);
  }

  @override
  Future<List<MattermostEmojiDto>> searchCustomEmojis(String term) async {
    final Response<Object?> response = await _post(
      '/emoji/search',
      data: <String, Object?>{'term': term},
    );
    return _dtoList(response.data, MattermostEmojiDto.fromJson);
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
  Future<MattermostPostListDto> getPostsAfter({
    required String channelId,
    required String postId,
    int page = 0,
    int perPage = 60,
  }) async {
    final Response<Object?> response = await _get(
      '/channels/${Uri.encodeComponent(channelId)}/posts',
      queryParameters: <String, Object?>{
        'after': postId,
        'page': page,
        'per_page': perPage,
      },
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostDto> getPost(String postId) async {
    final Response<Object?> response = await _get(
      '/posts/${Uri.encodeComponent(postId)}',
    );
    return MattermostPostDto.fromJson(_object(response.data));
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
  Future<MattermostPostListDto> getUnreadPostsForChannel({
    required String userId,
    required String channelId,
    int limitBefore = 0,
    int limitAfter = 200,
  }) async {
    final Response<Object?> response = await _get(
      '/users/${Uri.encodeComponent(userId)}'
      '/channels/${Uri.encodeComponent(channelId)}/posts/unread',
      queryParameters: <String, Object?>{
        'limit_before': limitBefore,
        'limit_after': limitAfter,
      },
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<List<MattermostPostDto>> getPostsByIds(List<String> postIds) async {
    if (postIds.isEmpty) return const <MattermostPostDto>[];
    final Response<Object?> response = await _post(
      '/posts/ids',
      data: jsonEncode(postIds),
    );
    return _dtoList(response.data, MattermostPostDto.fromJson);
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
  Future<MattermostPostActionResponseDto> executePostAction({
    required String postId,
    required String actionId,
    required MattermostPostActionRequestDto request,
  }) async {
    final Response<Object?> response = await _post(
      '/posts/${Uri.encodeComponent(postId)}/actions/${Uri.encodeComponent(actionId)}',
      data: request.toJson(),
    );
    return MattermostPostActionResponseDto.fromJson(_object(response.data));
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
      '/users/${Uri.encodeComponent(userId)}'
      '/teams/${Uri.encodeComponent(teamId)}'
      '/threads/${Uri.encodeComponent(threadId)}/read/$timestamp',
    );
  }

  @override
  Future<void> viewChannel({
    required String userId,
    required String channelId,
    String? previousChannelId,
  }) => _post(
    '/channels/members/${Uri.encodeComponent(userId)}/view',
    data: <String, Object?>{
      'channel_id': channelId,
      if (previousChannelId case final String value) 'prev_channel_id': value,
    },
  );

  @override
  Future<void> followThread({
    required String userId,
    required String teamId,
    required String threadId,
  }) => _put(_threadFollowingPath(userId, teamId, threadId));

  @override
  Future<void> unfollowThread({
    required String userId,
    required String teamId,
    required String threadId,
  }) => _delete(_threadFollowingPath(userId, teamId, threadId));

  @override
  Future<MattermostUserThreadDto?> getUserThread({
    required String userId,
    required String teamId,
    required String threadId,
  }) async {
    try {
      final Response<Object?> response = await _get(
        '/users/${Uri.encodeComponent(userId)}'
        '/teams/${Uri.encodeComponent(teamId)}'
        '/threads/${Uri.encodeComponent(threadId)}',
      );
      return MattermostUserThreadDto.fromJson(_object(response.data));
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<MattermostPreferenceDto>> getPreferencesByCategory({
    required String userId,
    required String category,
  }) async {
    final Response<Object?> response = await _get(
      '/users/${Uri.encodeComponent(userId)}'
      '/preferences/${Uri.encodeComponent(category)}',
    );
    return _dtoList(response.data, MattermostPreferenceDto.fromJson);
  }

  @override
  Future<void> savePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) => _put(
    '/users/${Uri.encodeComponent(userId)}/preferences',
    data: preferences
        .map((MattermostPreferenceDto value) => value.toJson())
        .toList(),
  );

  @override
  Future<void> deletePreferences({
    required String userId,
    required List<MattermostPreferenceDto> preferences,
  }) => _post(
    '/users/${Uri.encodeComponent(userId)}/preferences/delete',
    data: preferences
        .map((MattermostPreferenceDto value) => value.toJson())
        .toList(),
  );

  static String _threadFollowingPath(
    String userId,
    String teamId,
    String threadId,
  ) =>
      '/users/${Uri.encodeComponent(userId)}'
      '/teams/${Uri.encodeComponent(teamId)}'
      '/threads/${Uri.encodeComponent(threadId)}/following';

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

  Future<Response<Object?>> _post(
    String path, {
    Object? data,
    Map<String, Object?>? queryParameters,
  }) => _withCancellation(
    (CancelToken? cancelToken) => _dio.post<Object?>(
      path,
      data: data,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: Options(contentType: Headers.jsonContentType),
    ),
  );

  Future<Response<Object?>> _put(String path, {Object? data}) =>
      _withCancellation(
        (CancelToken? cancelToken) => _dio.put<Object?>(
          path,
          data: data,
          cancelToken: cancelToken,
          options: Options(contentType: Headers.jsonContentType),
        ),
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
