import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/viewed_channel_posts.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/viewed_channel_posts_repository.dart';

/// Stores one content-free set of individually viewed post ids per channel.
final class MattermostViewedChannelPostsRepository
    extends ViewedChannelPostsRepository {
  MattermostViewedChannelPostsRepository({required MattermostApi api})
    : _api = api;

  static const String category = 'inbox_viewed_posts';
  static const int _maxPreferenceValueLength = 20000;

  final MattermostApi _api;
  Future<void> _mutationTail = Future<void>.value();

  @override
  Future<ViewedChannelPostsSnapshot> load({
    required AuthSession session,
  }) async {
    final List<MattermostPreferenceDto> preferences;
    try {
      preferences = await _api.getPreferencesByCategory(
        userId: session.userId,
        category: category,
      );
    } on DioException catch (error) {
      if (!_isMissingCategory(error)) rethrow;
      return ViewedChannelPostsSnapshot(const <String, Set<String>>{});
    }
    final Map<String, Set<String>> byChannel = <String, Set<String>>{};
    for (final MattermostPreferenceDto preference in preferences) {
      final ({String channelId, Set<String> postIds})? parsed = _parse(
        preference,
        session.userId,
      );
      if (parsed == null) continue;
      byChannel
          .putIfAbsent(parsed.channelId, () => <String>{})
          .addAll(parsed.postIds);
    }
    return ViewedChannelPostsSnapshot(byChannel);
  }

  @override
  Future<void> add({
    required AuthSession session,
    required String channelId,
    required String postId,
  }) => _enqueue(() async {
    if (channelId.isEmpty || postId.isEmpty) return;
    final ViewedChannelPostsSnapshot current = await load(session: session);
    final List<String> postIds = <String>{
      ...current.forChannel(channelId),
      postId,
    }.toList()..sort();
    final String value = _encode(channelId, postIds);
    if (value.length > _maxPreferenceValueLength) {
      throw StateError('Viewed post preference exceeds Mattermost limit');
    }
    await _api.savePreferences(
      userId: session.userId,
      preferences: <MattermostPreferenceDto>[
        MattermostPreferenceDto(
          userId: session.userId,
          category: category,
          name: channelId,
          value: value,
        ),
      ],
    );
  });

  @override
  Future<void> removeChannel({
    required AuthSession session,
    required String channelId,
  }) => _enqueue(() async {
    if (channelId.isEmpty) return;
    await _api.deletePreferences(
      userId: session.userId,
      preferences: <MattermostPreferenceDto>[
        MattermostPreferenceDto(
          userId: session.userId,
          category: category,
          name: channelId,
          value: '',
        ),
      ],
    );
  });

  Future<void> _enqueue(Future<void> Function() mutation) {
    final Future<void> operation = _mutationTail.then((_) => mutation());
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static ({String channelId, Set<String> postIds})? _parse(
    MattermostPreferenceDto preference,
    String currentUserId,
  ) {
    if (preference.userId != currentUserId ||
        preference.category != category ||
        preference.name.isEmpty ||
        preference.value.length > _maxPreferenceValueLength) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(preference.value);
      if (decoded is! Map<Object?, Object?> ||
          decoded['v'] != 1 ||
          decoded['channel_id'] != preference.name ||
          decoded['post_ids'] is! List<Object?>) {
        return null;
      }
      final List<Object?> rawIds = decoded['post_ids']! as List<Object?>;
      final Set<String> postIds = rawIds
          .whereType<String>()
          .where((String id) => id.isNotEmpty)
          .toSet();
      if (postIds.isEmpty) return null;
      return (channelId: preference.name, postIds: postIds);
    } on FormatException {
      return null;
    }
  }

  static String _encode(String channelId, List<String> postIds) => jsonEncode(
    <String, Object?>{'v': 1, 'channel_id': channelId, 'post_ids': postIds},
  );

  static bool _isMissingCategory(DioException error) {
    if (error.response?.statusCode != 404) return false;
    final Object? data = error.response?.data;
    return data is Map<Object?, Object?> &&
        data['id'] == 'api.preference.preferences_category.get.app_error';
  }
}
