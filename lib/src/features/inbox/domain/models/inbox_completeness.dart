/// The confidence level of a network-first Inbox snapshot.
///
/// A snapshot remains usable in every state. The value tells consumers whether
/// its attention candidates were reconstructed exactly, best-effort for
/// historical mentions, or bounded by a safety cap.
enum InboxCompleteness {
  exact,
  approximateMentions,
  truncated;

  /// Combines independent source results without overstating completeness.
  static InboxCompleteness mostLimited(Iterable<InboxCompleteness> values) {
    InboxCompleteness result = InboxCompleteness.exact;
    for (final InboxCompleteness value in values) {
      if (value == InboxCompleteness.truncated) return value;
      if (value == InboxCompleteness.approximateMentions) result = value;
    }
    return result;
  }
}

/// A content-free reason why an Inbox source could not be exact.
///
/// These closed codes deliberately carry no message text, usernames, URLs,
/// cookies, tokens, or other user-provided values. Source implementations may
/// report only these codes to diagnostics and state consumers.
enum InboxSourceDiagnosticCode {
  mentionReconstructionMismatch,
  unreadRangeSafetyCapReached,
  unreadRangeCursorLoopDetected,
  unreadRangeCounterMismatch,
  postponedHydrationUnavailable,
  sourceRequestFailed,
  malformedSourcePayload,
}

/// Stable, content-free identifiers for independently loaded Inbox sources.
enum InboxSourceScope { followedThreads, unreadChannelPosts, postponed }

/// A source-local failure carried with an otherwise useful snapshot.
///
/// It intentionally excludes exception text and transport metadata, which can
/// contain sensitive server or user-provided content.
final class InboxSourceFailure {
  const InboxSourceFailure({
    required this.scope,
    this.code = InboxSourceDiagnosticCode.sourceRequestFailed,
  });

  final InboxSourceScope scope;
  final InboxSourceDiagnosticCode code;

  @override
  bool operator ==(Object other) =>
      other is InboxSourceFailure && other.scope == scope && other.code == code;

  @override
  int get hashCode => Object.hash(scope, code);
}
