import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';

/// Candidates split by whether they currently belong to the open channel.
final class MentionSearchResult {
  const MentionSearchResult({
    required this.channelMembers,
    required this.notInChannel,
  });

  final List<MentionCandidate> channelMembers;
  final List<MentionCandidate> notInChannel;

  bool get isEmpty => channelMembers.isEmpty && notInChannel.isEmpty;
  bool get isNotEmpty => !isEmpty;

  List<MentionCandidate> forGroup(MentionCandidateGroup group) =>
      switch (group) {
        MentionCandidateGroup.channelMembers => channelMembers,
        MentionCandidateGroup.notInChannel => notInChannel,
      };
}
