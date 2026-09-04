import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

enum InboxConnectionStatus { connecting, connected, disconnected }

sealed class InboxRealtimeEvent {
  const InboxRealtimeEvent();
}

final class InboxConnectionChanged extends InboxRealtimeEvent {
  const InboxConnectionChanged(this.status);

  final InboxConnectionStatus status;
}

/// A root-post replacement. A null candidate removes the post (or a thread
/// whose root has this ID) from the current projection.
final class InboxPostChanged extends InboxRealtimeEvent {
  const InboxPostChanged({required this.postId, required this.candidate});

  final String postId;
  final InboxPostCandidate? candidate;
}

/// The transport observed a change that cannot be safely represented as a
/// local post delta, so the repository snapshot must be rebuilt atomically.
final class InboxRefreshRequired extends InboxRealtimeEvent {
  const InboxRefreshRequired();
}
