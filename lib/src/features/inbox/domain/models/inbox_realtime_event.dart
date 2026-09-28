import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';

enum InboxConnectionStatus { connecting, connected, disconnected }

sealed class InboxRealtimeEvent {
  const InboxRealtimeEvent();
}

/// The semantic operation represented by a root-post websocket event.
///
/// A nullable candidate alone is not enough to describe a post change: an
/// ineligible create must be ignored, rather than accidentally interpreted as
/// a deletion. Keeping the operation typed also lets the domain reducer retain
/// the original Inbox membership when a post is edited.
enum InboxPostChangeKind { created, edited, deleted }

/// A realtime event carrying the transport sequence that established its
/// order. Connection state deliberately has no sequence, but every decoded
/// server event does. The Inbox snapshot boundary uses this to replay buffered
/// deltas deterministically.
abstract interface class InboxSequencedRealtimeEvent {
  int get sequence;
}

final class InboxConnectionChanged extends InboxRealtimeEvent {
  const InboxConnectionChanged(this.status);

  final InboxConnectionStatus status;
}

/// A typed root-post delta.
///
/// A [created] delta carries an eligible candidate, [edited] carries a preview
/// candidate only when the existing projection can be safely updated, and a
/// [deleted] delta never needs candidate content.
final class InboxPostChanged extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxPostChanged({
    required this.postId,
    required this.candidate,
    InboxPostChangeKind? kind,
    this.sequence = 0,
    this.mentions = const <String>[],
    this.followers = const <String>[],
    this.channelType,
  }) : kind =
           kind ??
           (candidate == null
               ? InboxPostChangeKind.deleted
               : InboxPostChangeKind.created);

  final String postId;
  final InboxPostCandidate? candidate;
  final InboxPostChangeKind kind;
  @override
  final int sequence;

  /// Server-authoritative users mentioned by this post, when supplied.
  final List<String> mentions;

  /// Followers included by the server for a followed-thread notification.
  final List<String> followers;

  /// Mattermost wire channel type (`D`, `G`, `O`, `P`) when supplied.
  final String? channelType;
}

/// The personalized unread counters sent for a followed CRT thread.
final class InboxThreadUpdated extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxThreadUpdated({
    required this.sequence,
    required this.rootPostId,
    this.channelId,
    this.unreadReplies,
    this.unreadMentions,
    this.isFollowing,
    this.isInboxEligible,
    this.candidate,
    this.reactivatePostponed = false,
    this.recoveryRequired = false,
  });

  @override
  final int sequence;
  final String rootPostId;
  final String? channelId;
  final int? unreadReplies;
  final int? unreadMentions;
  final bool? isFollowing;

  /// The data layer's desktop-thread eligibility result. A null value means
  /// the websocket payload did not provide enough trusted scope to decide.
  final bool? isInboxEligible;

  /// A bounded, authoritative hydration of the followed thread when one was
  /// needed to create or replace its displayable projection.
  final InboxThreadCandidate? candidate;

  /// Set only after the durable Postponed preference was removed. An explicit
  /// mention by itself is not authorization to move a user-owned item to New.
  final bool reactivatePostponed;

  /// The existing projection must be retained and reconciled later. This is
  /// intentionally distinct from an ineligible thread, which is removable.
  final bool recoveryRequired;
}

/// A server-side change to CRT following state.
final class InboxThreadFollowChanged extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxThreadFollowChanged({
    required this.sequence,
    required this.rootPostId,
    this.isFollowing,
    this.candidate,
    this.recoveryRequired = false,
  });

  @override
  final int sequence;
  final String rootPostId;
  final bool? isFollowing;
  final InboxThreadCandidate? candidate;
  final bool recoveryRequired;
}

/// A server-side read-boundary update for a CRT thread.
final class InboxThreadReadChanged extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxThreadReadChanged({
    required this.sequence,
    required this.rootPostId,
  });

  @override
  final int sequence;
  final String rootPostId;
}

/// A single preference record carried by one of Mattermost's preference
/// realtime events. The names remain opaque to domain policies until the
/// specific setting owns a reducer.
final class InboxPreferenceChange {
  const InboxPreferenceChange({
    required this.category,
    required this.name,
    this.value,
  });

  final String category;
  final String name;

  /// Null represents a deleted preference record.
  final String? value;
}

/// A tolerant projection of one or more preference records.
final class InboxPreferencesChanged extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxPreferencesChanged({
    required this.sequence,
    required this.changes,
  });

  @override
  final int sequence;
  final List<InboxPreferenceChange> changes;
}

/// The context used to determine Inbox eligibility changed on the server.
///
/// These events deliberately do not carry the server payload. The current
/// projection cannot safely derive all affected candidates from a partial
/// membership or notification update, so the controller requests one bounded
/// authoritative reconciliation instead.
enum InboxEligibilityContextChangeKind {
  desktopNotifications,
  channelMembership,
  directOrGroupAdded,
  currentUser,
}

final class InboxEligibilityContextChanged extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxEligibilityContextChanged({
    required this.sequence,
    required this.kind,
  });

  @override
  final int sequence;
  final InboxEligibilityContextChangeKind kind;
}

/// The scope that an authoritative realtime reconciliation must rebuild.
///
/// A postponed preference only owns the durable Postponed queue; replaying it
/// must not reload unrelated unread ranges or followed-thread pages.
enum InboxRefreshScope { full, postponed }

/// The transport observed a change that cannot be safely represented as a
/// local post delta, so the repository snapshot must be rebuilt atomically.
final class InboxRefreshRequired extends InboxRealtimeEvent
    implements InboxSequencedRealtimeEvent {
  const InboxRefreshRequired({
    this.sequence = 0,
    this.scope = InboxRefreshScope.full,
  });

  @override
  final int sequence;
  final InboxRefreshScope scope;
}
