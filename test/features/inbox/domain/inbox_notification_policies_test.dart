import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_notification_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';

void main() {
  group('desktop-only Inbox eligibility', () {
    const InboxUserNotificationSettings userAll = InboxUserNotificationSettings(
      desktop: InboxDesktopNotificationLevel.all,
      desktopThreads: InboxDesktopNotificationLevel.all,
    );
    const InboxUserNotificationSettings userMention =
        InboxUserNotificationSettings(
          desktop: InboxDesktopNotificationLevel.mention,
          desktopThreads: InboxDesktopNotificationLevel.mention,
        );

    test('ordinary channel posts require all mark-unread and desktop all', () {
      expect(
        resolvesToAllMessagesSubscription(
          channel: const InboxChannelNotificationSettings(
            markUnread: InboxMarkUnread.all,
          ),
          user: userAll,
        ),
        isTrue,
      );
      expect(
        resolvesToAllMessagesSubscription(
          channel: const InboxChannelNotificationSettings(
            desktop: InboxDesktopNotificationLevel.all,
            markUnread: InboxMarkUnread.mention,
          ),
          user: userAll,
        ),
        isFalse,
      );
    });

    test('channel desktop overrides user desktop', () {
      expect(
        resolvesToAllMessagesSubscription(
          channel: const InboxChannelNotificationSettings(
            desktop: InboxDesktopNotificationLevel.mention,
            markUnread: InboxMarkUnread.all,
          ),
          user: userAll,
        ),
        isFalse,
      );
      expect(
        resolvesToAllMessagesSubscription(
          channel: const InboxChannelNotificationSettings(
            desktop: InboxDesktopNotificationLevel.all,
            markUnread: InboxMarkUnread.all,
          ),
          user: userMention,
        ),
        isTrue,
      );
    });

    test('user and channel desktop matrix only admits effective all', () {
      const List<
        ({
          InboxDesktopNotificationLevel channel,
          InboxDesktopNotificationLevel user,
          bool expected,
        })
      >
      cases =
          <
            ({
              InboxDesktopNotificationLevel channel,
              InboxDesktopNotificationLevel user,
              bool expected,
            })
          >[
            (
              channel: InboxDesktopNotificationLevel.inherit,
              user: InboxDesktopNotificationLevel.all,
              expected: true,
            ),
            (
              channel: InboxDesktopNotificationLevel.inherit,
              user: InboxDesktopNotificationLevel.mention,
              expected: false,
            ),
            (
              channel: InboxDesktopNotificationLevel.all,
              user: InboxDesktopNotificationLevel.none,
              expected: true,
            ),
            (
              channel: InboxDesktopNotificationLevel.mention,
              user: InboxDesktopNotificationLevel.all,
              expected: false,
            ),
            (
              channel: InboxDesktopNotificationLevel.none,
              user: InboxDesktopNotificationLevel.all,
              expected: false,
            ),
            (
              channel: InboxDesktopNotificationLevel.unknown,
              user: InboxDesktopNotificationLevel.all,
              expected: false,
            ),
          ];

      for (final (
            :InboxDesktopNotificationLevel channel,
            :InboxDesktopNotificationLevel user,
            :bool expected,
          )
          in cases) {
        expect(
          resolvesToAllMessagesSubscription(
            channel: InboxChannelNotificationSettings(
              desktop: channel,
              markUnread: InboxMarkUnread.all,
            ),
            user: InboxUserNotificationSettings(desktop: user),
          ),
          expected,
          reason: 'channel=$channel, user=$user',
        );
      }
    });

    test(
      'inherit and unknown desktop values conservatively resolve to mention',
      () {
        expect(
          resolveInboxDesktopNotificationLevel(
            channel: InboxDesktopNotificationLevel.inherit,
            user: InboxDesktopNotificationLevel.unknown,
          ),
          InboxDesktopNotificationLevel.mention,
        );
        expect(
          resolveInboxDesktopNotificationLevel(
            channel: InboxDesktopNotificationLevel.unknown,
            user: InboxDesktopNotificationLevel.all,
          ),
          InboxDesktopNotificationLevel.mention,
        );
      },
    );

    test('DM and GM include all and mention but exclude none', () {
      expect(
        isDirectMessageInboxEligible(
          channel: const InboxChannelNotificationSettings(),
          user: userAll,
        ),
        isTrue,
      );
      expect(
        isDirectMessageInboxEligible(
          channel: const InboxChannelNotificationSettings(),
          user: userMention,
        ),
        isTrue,
      );
      expect(
        isDirectMessageInboxEligible(
          channel: const InboxChannelNotificationSettings(),
          user: const InboxUserNotificationSettings(
            desktop: InboxDesktopNotificationLevel.none,
          ),
        ),
        isFalse,
      );
      expect(
        isDirectMessageInboxEligible(
          channel: const InboxChannelNotificationSettings(
            desktop: InboxDesktopNotificationLevel.none,
          ),
          user: userAll,
        ),
        isFalse,
      );
    });

    test('followed threads follow the desktop thread matrix', () {
      const InboxChannelNotificationSettings channel =
          InboxChannelNotificationSettings();
      expect(
        isFollowedThreadInboxEligible(
          channel: channel,
          user: userAll,
          unreadReplies: 1,
          unreadMentions: 0,
        ),
        isTrue,
      );
      expect(
        isFollowedThreadInboxEligible(
          channel: channel,
          user: userMention,
          unreadReplies: 1,
          unreadMentions: 0,
        ),
        isFalse,
      );
      expect(
        isFollowedThreadInboxEligible(
          channel: channel,
          user: userMention,
          unreadReplies: 1,
          unreadMentions: 1,
        ),
        isTrue,
      );
      expect(
        isFollowedThreadInboxEligible(
          channel: const InboxChannelNotificationSettings(
            desktop: InboxDesktopNotificationLevel.none,
          ),
          user: userAll,
          unreadReplies: 1,
          unreadMentions: 1,
        ),
        isFalse,
      );
      expect(
        isFollowedThreadInboxEligible(
          channel: const InboxChannelNotificationSettings(),
          user: const InboxUserNotificationSettings(
            desktop: InboxDesktopNotificationLevel.all,
            desktopThreads: InboxDesktopNotificationLevel.none,
          ),
          unreadReplies: 1,
          unreadMentions: 1,
        ),
        isFalse,
      );
      expect(
        isFollowedThreadInboxEligible(
          channel: channel,
          user: userMention,
          unreadReplies: 0,
          unreadMentions: 1,
        ),
        isTrue,
      );
      expect(
        isFollowedThreadInboxEligible(
          channel: channel,
          user: userAll,
          unreadReplies: 0,
          unreadMentions: 1,
        ),
        isFalse,
      );
    });
  });

  test('classifies direct and keyword mentions before an all subscription', () {
    expect(
      classifyInboxAttention(
        message: 'hello @Me',
        username: 'me',
        firstName: '',
        mentionKeys: 'urgent',
        firstNameEnabled: false,
        channelMentionsEnabled: false,
        ignoreChannelMentions: false,
        allMessagesSubscription: true,
      ),
      InboxAttentionReason.directMention,
    );
    expect(
      classifyInboxAttention(
        message: 'This is urgent!',
        username: 'me',
        firstName: '',
        mentionKeys: 'urgent',
        firstNameEnabled: false,
        channelMentionsEnabled: false,
        ignoreChannelMentions: false,
        allMessagesSubscription: true,
      ),
      InboxAttentionReason.keywordMention,
    );
  });
}
