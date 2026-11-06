abstract final class ChannelSidebarStrings {
  static const String threads = 'Threads';
  static const String title = 'Teams and channels';
  static const String loading = 'Loading teams and channels';
  static const String empty = 'No channels available';
  static const String loadFailed = 'Could not load teams and channels';
  static const String refreshFailed =
      'Could not refresh. Showing previously loaded data.';
  static const String retry = 'Retry';
  static const String categoryUpdateFailed =
      'Category changed locally; could not sync with server.';
  static const String inbox = 'Inbox';
  static const String searchHint = 'Find channels and dialogs';
  static const String clearSearch = 'Clear channel search';
  static const String hideReadChannels = 'Hide read channels';
  static const String showReadChannels = 'Show read channels';
  static const String noUnreadChannels = 'No unread channels';
  static const String hideFolderHeadings = 'Hide folder headings';
  static const String showFolderHeadings = 'Show folder headings';
  static const String preferencesSaveFailed =
      'Could not save sidebar settings. Try again.';
  static const String noSearchResults = 'No matching channels or dialogs';
  static const String markUnread = 'Mark as unread';
  static const String addFavorite = 'Add to favorites';
  static const String removeFavorite = 'Remove from favorites';
  static const String muteChannel = 'Mute channel';
  static const String unmuteChannel = 'Unmute channel';
  static const String moveTo = 'Move to…';
  static const String closeConversation = 'Close conversation';
  static const String leaveChannel = 'Покинуть канал';
  static const String leaveChannelTitle = 'Покинуть канал?';
  static const String leaveChannelDescription =
      'Вы перестанете получать сообщения из этого канала.';
  static const String leavePrivateChannelDescription =
      'Чтобы вернуться в приватный канал, потребуется приглашение.';
  static const String cancel = 'Отмена';
  static const String confirmLeaveChannel = 'Покинуть';
  static const String channelActionFailed =
      'Could not update channel. Try again.';

  static String unreadChannel(String channelName) => '$channelName, unread';
}
