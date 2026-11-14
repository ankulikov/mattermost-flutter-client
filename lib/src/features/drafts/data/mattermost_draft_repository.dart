import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:mattermost_flutter/src/data/api/dto/mattermost_draft_dto.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft.dart';
import 'package:mattermost_flutter/src/features/drafts/domain/draft_repository.dart';

final class MattermostDraftRepository implements DraftRepository {
  const MattermostDraftRepository(this._api);
  final MattermostApi _api;

  @override
  Future<List<Draft>> listTeamDrafts(String teamId) async {
    try {
      return (await _api.listTeamDrafts(
        teamId,
      )).map(_fromDto).toList(growable: false);
    } on DioException catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<Draft?> saveDraft(Draft draft) async {
    try {
      final MattermostDraftDto? result = await _api.saveDraft(
        MattermostDraftDto(
          channelId: draft.channelId,
          message: draft.message,
          rootId: draft.rootId,
          fileIds: draft.fileIds,
          type: draft.type,
          props: draft.props,
          priority: draft.priority,
        ),
      );
      return result == null ? null : _fromDto(result);
    } on DioException catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> deleteDraft({required String channelId, String? rootId}) async {
    try {
      await _api.deleteDraft(channelId: channelId, rootId: rootId);
    } on DioException catch (error) {
      throw _mapFailure(error);
    }
  }

  DraftSyncException _mapFailure(DioException error) {
    final status = error.response?.statusCode;
    final retryable =
        status == null ||
        status == 408 ||
        status == 429 ||
        (status >= 500 && status < 600 && status != 501);
    final value = error.response?.headers.value('retry-after');
    Duration? retryAfter;
    if (value != null) {
      final seconds = int.tryParse(value.trim());
      if (seconds != null) {
        retryAfter = Duration(seconds: seconds < 0 ? 0 : seconds);
      } else {
        try {
          final when = DateFormat(
            "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
            'en_US',
          ).parseUtc(value);
          final remaining = when.difference(DateTime.now().toUtc());
          retryAfter = remaining.isNegative ? Duration.zero : remaining;
        } on FormatException {
          // Invalid retry headers fall back to exponential delay.
        }
      }
    }
    return DraftSyncException(
      retryable: retryable,
      retryAfter: retryAfter,
      unsupported: status == 501,
    );
  }

  Draft _fromDto(MattermostDraftDto dto) {
    return Draft(
      userId: dto.userId,
      channelId: dto.channelId,
      rootId: dto.rootId,
      message: dto.message,
      fileIds: dto.fileIds,
      fileInfos: dto.fileInfos,
      createAt: dto.createAt,
      updateAt: dto.updateAt,
      type: dto.type,
      props: dto.props,
      priority: dto.priority,
    );
  }
}
