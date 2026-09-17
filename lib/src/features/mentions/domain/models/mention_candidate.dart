import 'package:mattermost_flutter/src/domain/models/user.dart';

/// A person which can be inserted as a user mention.
final class MentionCandidate {
  const MentionCandidate({required this.user});

  final UserSummary user;
}

/// The server-provided membership sections shown by the mention picker.
enum MentionCandidateGroup { channelMembers, notInChannel }
