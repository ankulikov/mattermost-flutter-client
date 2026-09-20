import 'dart:convert';

import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/realtime/session_realtime_service.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/post_action.dart';
import 'package:mattermost_flutter/src/domain/models/rich_attachment.dart';
import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/domain/repositories/message_mapper.dart';
import 'package:mattermost_flutter/src/domain/repositories/post_action_repository.dart';
import 'package:mattermost_flutter/src/domain/repositories/user_repository.dart';

final class MattermostPostActionRepository implements PostActionRepository {
  const MattermostPostActionRepository({
    required MattermostApi api,
    required MessageMapper<MattermostPostDto, UserSummary> messageMapper,
    required UserRepository users,
    SessionRealtimeService? realtime,
  }) : _api = api,
       _messageMapper = messageMapper,
       _users = users,
       _realtime = realtime;

  final MattermostApi _api;
  final MessageMapper<MattermostPostDto, UserSummary> _messageMapper;
  final UserRepository _users;
  final SessionRealtimeService? _realtime;

  @override
  Future<PostActionResult> execute({
    required AuthSession session,
    required String postId,
    required String actionId,
    RichAttachmentActionToken? token,
    String? selectedOption,
  }) async {
    final MattermostPostActionResponseDto response = await _api
        .executePostAction(
          postId: postId,
          actionId: actionId,
          request: MattermostPostActionRequestDto(
            cookie: token?.value,
            selectedOption: selectedOption,
          ),
        );
    final MattermostPostDto refreshed = await _api.getPost(postId);
    final List<UserSummary> users = await _users.getUsers(<String>[
      refreshed.userId,
    ], freshness: UserFreshness.fresh);
    final ChannelPost updatedPost = _messageMapper
        .map(
          posts: <MattermostPostDto>[refreshed],
          users: users,
          currentUserId: session.userId,
          includeDeleted: true,
        )
        .single;
    return PostActionResult(
      updatedPost: updatedPost,
      gotoLocation: response.gotoLocation,
    );
  }

  @override
  Stream<PostActionRealtimeEvent> watchRealtime({
    required AuthSession session,
  }) {
    final SessionRealtimeService? realtime = _realtime;
    if (realtime == null) {
      return const Stream<PostActionRealtimeEvent>.empty();
    }
    return realtime
        .watch(
          session: session,
          eventNames: const <String>{'post_edited', 'ephemeral_message'},
        )
        .asyncMap((SessionRealtimeSignal signal) async {
          if (signal case SessionRealtimeEventReceived(:final event)) {
            final MattermostPostDto? raw = _postFromEvent(event.data);
            if (raw == null || raw.id.isEmpty) return null;
            if (event.name == 'ephemeral_message') {
              return raw.message.isEmpty || raw.rootId.isEmpty
                  ? null
                  : PostActionEphemeralFeedback(
                      channelId: raw.channelId,
                      sourceRootPostId: raw.rootId,
                      message: raw.message,
                    );
            }
            try {
              return PostActionPostUpdated(await _mapPost(raw, session));
            } on Object {
              // Isolate malformed author/post projections to one event.
              return null;
            }
          }
          return null;
        })
        .where((PostActionRealtimeEvent? event) => event != null)
        .cast<PostActionRealtimeEvent>();
  }

  Future<ChannelPost> _mapPost(
    MattermostPostDto raw,
    AuthSession session,
  ) async {
    final List<UserSummary> authors = await _users.getUsers(<String>[
      raw.userId,
    ], freshness: UserFreshness.fresh);
    return _messageMapper
        .map(
          posts: <MattermostPostDto>[raw],
          users: authors,
          currentUserId: session.userId,
          includeDeleted: true,
        )
        .single;
  }

  static MattermostPostDto? _postFromEvent(Map<String, Object?> data) {
    final Object? encoded = data['post'];
    final Object? decoded;
    try {
      decoded = encoded is String ? jsonDecode(encoded) : encoded;
    } on FormatException {
      return null;
    }
    if (decoded is! Map<Object?, Object?>) return null;
    return MattermostPostDto.fromJson(
      decoded.map(
        (Object? key, Object? value) => MapEntry<String, Object?>(
          key is String ? key : key.toString(),
          value,
        ),
      ),
    );
  }
}
