/// Returns whether a channel's effective notification settings opt it into the
/// Inbox all-messages source.
///
/// Mattermost has separate transport settings, so either desktop or push set
/// to `all` is sufficient. A channel-level `default` inherits the user value.
bool resolvesToAllMessagesSubscription({
  required String memberMarkUnread,
  required String memberDesktop,
  required String memberPush,
  required String userDesktop,
  required String userPush,
}) {
  if (memberMarkUnread != 'all') return false;
  return _effective(memberDesktop, userDesktop) == 'all' ||
      _effective(memberPush, userPush) == 'all';
}

String _effective(String channelValue, String userValue) =>
    channelValue == 'default' || channelValue.isEmpty
    ? userValue
    : channelValue;
