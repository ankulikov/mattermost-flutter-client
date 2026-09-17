import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';

/// Candidates split by whether they currently belong to the open channel.
final class MentionSearchResult {
  const MentionSearchResult({
    required this.channelMembers,
    this.groupMentions = const <GroupMentionCandidate>[],
    required this.notInChannel,
  });

  final List<MentionCandidate> channelMembers;
  final List<GroupMentionCandidate> groupMentions;
  final List<MentionCandidate> notInChannel;

  bool get isEmpty =>
      channelMembers.isEmpty && groupMentions.isEmpty && notInChannel.isEmpty;
  bool get isNotEmpty => !isEmpty;

  List<MentionSuggestion> forGroup(MentionCandidateGroup group) =>
      switch (group) {
        MentionCandidateGroup.channelMembers => channelMembers,
        MentionCandidateGroup.groupMentions => groupMentions,
        MentionCandidateGroup.notInChannel => notInChannel,
      };

  List<MentionSuggestion> get orderedSuggestions =>
      List<MentionSuggestion>.unmodifiable(<MentionSuggestion>[
        ...channelMembers,
        ...groupMentions,
        ...notInChannel,
      ]);
}
