import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';

void main() {
  test(
    'all messages requires all mark-unread and an effective all transport',
    () {
      expect(
        resolvesToAllMessagesSubscription(
          memberMarkUnread: 'all',
          memberDesktop: 'default',
          memberPush: 'mention',
          userDesktop: 'all',
          userPush: 'mention',
        ),
        isTrue,
      );
      expect(
        resolvesToAllMessagesSubscription(
          memberMarkUnread: 'mention',
          memberDesktop: 'all',
          memberPush: 'all',
          userDesktop: 'all',
          userPush: 'all',
        ),
        isFalse,
      );
    },
  );

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

  test('classifies a mention of a current user group', () {
    expect(
      classifyInboxAttention(
        message: 'Please review this, @Backend-Team.',
        username: 'me',
        firstName: '',
        mentionKeys: '',
        firstNameEnabled: false,
        channelMentionsEnabled: false,
        ignoreChannelMentions: false,
        allMessagesSubscription: false,
        groupMentionNames: const <String>['backend-team'],
      ),
      InboxAttentionReason.groupMention,
    );
  });
}
