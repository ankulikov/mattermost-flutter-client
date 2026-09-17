import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_search_result.dart';

/// Search boundary for user mentions in a team channel.
abstract interface class MentionRepository {
  Future<MentionSearchResult> autocomplete({
    required String teamId,
    required String channelId,
    required String term,
    int limit = 30,
  });

  /// Resolves exact group handles so rendered messages can distinguish a group
  /// mention from unresolved user text without changing its visible name.
  Future<List<GroupMention>> resolveGroupsByNames(List<String> names);
}
