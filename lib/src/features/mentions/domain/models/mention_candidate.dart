import 'package:mattermost_flutter/src/domain/models/user.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/models/group_mention.dart';

/// A selectable item in the shared at-mention suggestion list.
sealed class MentionSuggestion {
  const MentionSuggestion();

  String get stableId;
  String get mentionName;
}

/// A person which can be inserted as a user mention.
final class MentionCandidate extends MentionSuggestion {
  const MentionCandidate({required this.user});

  final UserSummary user;

  @override
  String get stableId => 'user:${user.id}';

  @override
  String get mentionName => user.username;
}

/// A user group which can be inserted using its unchanged mention handle.
final class GroupMentionCandidate extends MentionSuggestion {
  const GroupMentionCandidate({required this.group});

  final GroupMention group;

  @override
  String get stableId => 'group:${group.id}';

  @override
  String get mentionName => group.name;
}

/// The server-provided membership sections shown by the mention picker.
enum MentionCandidateGroup { channelMembers, groupMentions, notInChannel }
