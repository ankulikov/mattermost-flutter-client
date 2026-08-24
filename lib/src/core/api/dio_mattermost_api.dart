import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/core/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/core/api/mattermost_api.dart';

final class DioMattermostApi implements MattermostApi {
  DioMattermostApi({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<MattermostUserDto> getCurrentUser() async {
    final Response<Object?> response = await _dio.get<Object?>('/users/me');
    return MattermostUserDto.fromJson(_object(response.data));
  }

  @override
  Future<List<MattermostTeamDto>> getTeamsForCurrentUser() async {
    final Response<Object?> response = await _dio.get<Object?>(
      '/users/me/teams',
    );
    return _dtoList(response.data, MattermostTeamDto.fromJson);
  }

  @override
  Future<List<MattermostChannelDto>> getChannelsForUser({
    required String userId,
    required String teamId,
    String? etag,
  }) async {
    final Response<Object?> response = await _dio.get<Object?>(
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
    final Response<Object?> response = await _dio.get<Object?>(
      '/users/$userId/teams/$teamId/channels/categories',
    );
    return MattermostChannelCategoriesDto.fromJson(_object(response.data));
  }

  @override
  Future<List<MattermostUserDto>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return const <MattermostUserDto>[];
    final Response<Object?> response = await _dio.post<Object?>(
      '/users/ids',
      data: jsonEncode(userIds),
    );
    return _dtoList(response.data, MattermostUserDto.fromJson);
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
    final Response<Object?> response = await _dio.post<Object?>(
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
  Future<MattermostPostListDto> getPostsForChannel({
    required String channelId,
    int page = 0,
    int perPage = 60,
    String? etag,
  }) async {
    final Response<Object?> response = await _dio.get<Object?>(
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
    final Response<Object?> response = await _dio.get<Object?>(
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
    final Response<Object?> response = await _dio.get<Object?>(
      '/channels/$channelId/posts',
      queryParameters: <String, Object?>{'since': since},
    );
    return MattermostPostListDto.fromJson(_object(response.data));
  }

  @override
  Future<MattermostPostListDto> getPostThread({
    required String rootPostId,
    int perPage = 60,
    String? fromPost,
    int? fromCreateAt,
    PostThreadDirection direction = PostThreadDirection.up,
  }) async {
    final Response<Object?> response = await _dio.get<Object?>(
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

  static Map<String, String>? _conditionalHeaders(String? etag) =>
      etag == null ? null : <String, String>{'If-None-Match': etag};

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
