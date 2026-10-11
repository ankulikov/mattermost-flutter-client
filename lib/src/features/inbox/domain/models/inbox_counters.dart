/// Durable, content-free summary used before the current Inbox snapshot loads.
final class InboxCounters {
  const InboxCounters({
    required this.newMessages,
    required this.postponedMessages,
  });

  static const InboxCounters empty = InboxCounters(
    newMessages: 0,
    postponedMessages: 0,
  );

  final int newMessages;
  final int postponedMessages;

  bool get hasNewMessages => newMessages > 0;
}
