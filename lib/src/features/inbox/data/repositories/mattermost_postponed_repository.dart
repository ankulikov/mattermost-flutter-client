import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/postponed_reference.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/repositories/postponed_repository.dart';

/// Persists one content-free postponed reference per Mattermost preference.
final class MattermostPostponedRepository extends PostponedRepository {
  MattermostPostponedRepository({required MattermostApi api}) : _api = api;

  static const String category = 'postponed_messages';
  static const int batchSize = 100;
  static const int _maxReferenceJsonCharacters = 4096;

  final MattermostApi _api;

  @override
  Future<PostponedReferencesSnapshot> load({
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
      return PostponedReferencesSnapshot(const <PostponedReference>[]);
    }
    final Map<String, PostponedReference> references =
        <String, PostponedReference>{};
    for (final MattermostPreferenceDto preference in preferences) {
      final PostponedReference? reference = _parse(preference, session.userId);
      if (reference == null) continue;
      final PostponedReference? existing = references[reference.canonicalId];
      if (existing == null || reference.addedAt.isAfter(existing.addedAt)) {
        references[reference.canonicalId] = reference;
      }
    }
    return PostponedReferencesSnapshot(references.values);
  }

  @override
  Future<void> save({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    final PostponedBatchOutcome outcome = await saveWithOutcome(
      session: session,
      references: references,
    );
    if (outcome.requiresReconciliation) {
      throw const PostponedBatchReconciliationRequired();
    }
  }

  @override
  Future<PostponedBatchOutcome> saveWithOutcome({
    required AuthSession session,
    required List<PostponedReference> references,
  }) => _mutateWithOutcome(
    references: references,
    mutate: (List<PostponedReference> batch) => _api.savePreferences(
      userId: session.userId,
      preferences: batch
          .map((PostponedReference reference) {
            return MattermostPreferenceDto(
              userId: session.userId,
              category: category,
              name: reference.canonicalId,
              value: jsonEncode(<String, Object?>{
                'v': 1,
                'post_id': reference.postId,
                'added_at': reference.addedAt.millisecondsSinceEpoch,
                if (reference.targetPostId != null)
                  'target_post_id': reference.targetPostId,
                'kind': reference.kind.name,
              }),
            );
          })
          .toList(growable: false),
    ),
  );

  @override
  Future<void> remove({
    required AuthSession session,
    required List<PostponedReference> references,
  }) async {
    final PostponedBatchOutcome outcome = await removeWithOutcome(
      session: session,
      references: references,
    );
    if (outcome.requiresReconciliation) {
      throw const PostponedBatchReconciliationRequired();
    }
  }

  @override
  Future<PostponedBatchOutcome> removeWithOutcome({
    required AuthSession session,
    required List<PostponedReference> references,
  }) => _mutateWithOutcome(
    references: references,
    mutate: (List<PostponedReference> batch) => _api.deletePreferences(
      userId: session.userId,
      preferences: batch
          .map(
            (PostponedReference reference) => MattermostPreferenceDto(
              userId: session.userId,
              category: category,
              name: reference.canonicalId,
              value: '',
            ),
          )
          .toList(growable: false),
    ),
  );

  Future<PostponedBatchOutcome> _mutateWithOutcome({
    required List<PostponedReference> references,
    required Future<void> Function(List<PostponedReference> batch) mutate,
  }) async {
    final List<PostponedReference> requested = _deduplicate(references);
    final List<PostponedReference> confirmed = <PostponedReference>[];
    for (final List<PostponedReference> batch in _batches(requested)) {
      try {
        await mutate(batch);
      } on Object {
        // A transport failure cannot prove that the server rejected this
        // batch. Even the first batch therefore requires an authoritative
        // reload before presentation can claim a requested reference moved.
        return PostponedBatchOutcome(
          requested: requested,
          confirmed: confirmed,
          requiresReconciliation: true,
        );
      }
      confirmed.addAll(batch);
    }
    return PostponedBatchOutcome.confirmed(requested);
  }

  static List<PostponedReference> _deduplicate(
    Iterable<PostponedReference> references,
  ) {
    final Map<String, PostponedReference> unique =
        <String, PostponedReference>{};
    for (final PostponedReference reference in references) {
      unique.putIfAbsent(reference.canonicalId, () => reference);
    }
    return unique.values.toList(growable: false);
  }

  static PostponedReference? _parse(
    MattermostPreferenceDto preference,
    String currentUserId,
  ) {
    if (preference.userId != currentUserId ||
        preference.category != category ||
        preference.name.isEmpty ||
        preference.value.length > _maxReferenceJsonCharacters) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(preference.value);
      if (decoded is! Map<Object?, Object?>) return null;
      final Object? postId = decoded['post_id'];
      final Object? addedAt = decoded['added_at'];
      final Object? kind = decoded['kind'];
      if (postId is! String || postId != preference.name || kind is! String) {
        return null;
      }
      final int? milliseconds = switch (addedAt) {
        final int value => value,
        final String value => int.tryParse(value),
        _ => null,
      };
      final PostponedReferenceKind? referenceKind = switch (kind) {
        'post' => PostponedReferenceKind.post,
        'thread' => PostponedReferenceKind.thread,
        _ => null,
      };
      if (milliseconds == null || referenceKind == null || milliseconds < 0) {
        return null;
      }
      final Object? target = decoded['target_post_id'];
      return PostponedReference(
        postId: postId,
        kind: referenceKind,
        addedAt: DateTime.fromMillisecondsSinceEpoch(milliseconds),
        targetPostId: target is String && target.isNotEmpty ? target : null,
      );
    } on FormatException {
      return null;
    }
  }

  static Iterable<List<PostponedReference>> _batches(
    List<PostponedReference> references,
  ) sync* {
    for (var start = 0; start < references.length; start += batchSize) {
      yield references.sublist(
        start,
        start + batchSize > references.length
            ? references.length
            : start + batchSize,
      );
    }
  }

  static bool _isMissingCategory(DioException error) {
    if (error.response?.statusCode != 404) return false;
    final Object? data = error.response?.data;
    return data is Map<Object?, Object?> &&
        data['id'] == 'api.preference.preferences_category.get.app_error';
  }
}
