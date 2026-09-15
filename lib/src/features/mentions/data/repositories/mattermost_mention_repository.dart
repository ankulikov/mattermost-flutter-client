import 'package:mattermost_flutter/src/data/api/dto/mattermost_dtos.dart';
import 'package:mattermost_flutter/src/data/api/mattermost_api.dart';
import 'package:mattermost_flutter/src/data/mappers/user_mapper.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/policies/rank_mention_candidates.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/repositories/mention_repository.dart';

/// Network-backed mention search; it does not persist member or search data.
final class MattermostMentionRepository implements MentionRepository {
  MattermostMentionRepository({required MattermostApi api}) : _api = api;

  final MattermostApi _api;

  @override
  Future<MentionSearchResult> autocomplete({
    required String teamId,
    required String channelId,
    required String term,
    int limit = 30,
  }) async {
    final MattermostUserAutocompleteDto response = await _api.autocompleteUsers(
      teamId: teamId,
      channelId: channelId,
      name: term,
      limit: limit,
    );
    final Set<String> agentIds =
        response.agents
            ?.map((MattermostUserDto user) => user.id)
            .where((String id) => id.trim().isNotEmpty)
            .toSet() ??
        <String>{};
    final Set<String> seenIds = <String>{};
    final List<MentionCandidate> channelMembers = _candidates(
      response.users,
      agentIds: agentIds,
      seenIds: seenIds,
    );
    final List<MentionCandidate> notInChannel = _candidates(
      response.outOfChannel ?? const <MattermostUserDto>[],
      agentIds: agentIds,
      seenIds: seenIds,
    );
    return MentionSearchResult(
      channelMembers: rankMentionCandidates(channelMembers, term),
      notInChannel: rankMentionCandidates(notInChannel, term),
    );
  }

  static List<MentionCandidate> _candidates(
    Iterable<MattermostUserDto> users, {
    required Set<String> agentIds,
    required Set<String> seenIds,
  }) => List<MentionCandidate>.unmodifiable(
    users
        .where(
          (MattermostUserDto user) =>
              user.id.trim().isNotEmpty &&
              user.username.trim().isNotEmpty &&
              user.deleteAt == 0 &&
              !agentIds.contains(user.id) &&
              seenIds.add(user.id),
        )
        .map(
          (MattermostUserDto user) =>
              MentionCandidate(user: mapUserSummary(user)),
        ),
  );
}
