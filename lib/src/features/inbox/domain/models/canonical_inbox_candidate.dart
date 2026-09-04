import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

sealed class CanonicalInboxCandidate {
  const CanonicalInboxCandidate();
  String get canonicalId;
}

final class CanonicalThreadCandidate extends CanonicalInboxCandidate {
  const CanonicalThreadCandidate(this.candidate);

  final InboxThreadCandidate candidate;
  @override
  String get canonicalId => candidate.thread.id;
}

final class CanonicalDirectPostCandidate extends CanonicalInboxCandidate {
  const CanonicalDirectPostCandidate(this.candidate);

  final InboxPostCandidate candidate;
  @override
  String get canonicalId => candidate.post.id;
}

final class CanonicalChannelPostCandidate extends CanonicalInboxCandidate {
  const CanonicalChannelPostCandidate(this.candidate);

  final InboxPostCandidate candidate;
  @override
  String get canonicalId => candidate.post.id;
}
