/// Resolves the user's effective Mattermost timezone without exposing session
/// credentials or a transport DTO to presentation code.
abstract interface class MessageSearchTimezoneRepository {
  Future<MessageSearchTimezone> load();
}

final class MessageSearchTimezone {
  const MessageSearchTimezone({
    required this.timezoneId,
    required this.offsetSeconds,
  });

  /// IANA identifier when the server provided a valid one, otherwise null.
  final String? timezoneId;

  /// Computes the effective UTC offset for the supplied instant.
  final int Function(DateTime instant) offsetSeconds;
}
