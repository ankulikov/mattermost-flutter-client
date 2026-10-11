abstract final class ChannelMembersStrings {
  static const String title = 'Members';
  static const String close = 'Close members';
  static const String loading = 'Loading channel members';
  static const String loadFailed = 'Could not load channel members';
  static const String paginationFailed = 'Could not load more members';
  static const String empty = 'This channel has no members';
  static const String retry = 'Retry';
  static const String loadMore = 'Load more';
  static const String channelAdmin = 'Channel admin';

  static String count(int count) => count == 1 ? '1 member' : '$count members';
}
