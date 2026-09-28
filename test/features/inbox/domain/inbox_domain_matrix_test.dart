import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_notification_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_post_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_attention.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/notification_eligibility.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

void main() {
  group('desktop source matrix', () {
    test('applies every channel and user desktop combination consistently', () {
      for (final InboxDesktopNotificationLevel channel
          in InboxDesktopNotificationLevel.values) {
        for (final InboxDesktopNotificationLevel user
            in InboxDesktopNotificationLevel.values) {
          final InboxDesktopNotificationLevel expected = _effectiveDesktop(
            channel: channel,
            user: user,
          );
          final InboxChannelNotificationSettings channelSettings =
              InboxChannelNotificationSettings(
                desktop: channel,
                markUnread: InboxMarkUnread.all,
              );
          final InboxUserNotificationSettings userSettings =
              InboxUserNotificationSettings(desktop: user);

          expect(
            resolveInboxDesktopNotificationLevel(channel: channel, user: user),
            expected,
            reason: 'effective desktop channel=$channel user=$user',
          );
          expect(
            resolvesToAllMessagesSubscription(
              channel: channelSettings,
              user: userSettings,
            ),
            expected == InboxDesktopNotificationLevel.all,
            reason: 'all activity channel=$channel user=$user',
          );
          expect(
            isDirectMessageInboxEligible(
              channel: channelSettings,
              user: userSettings,
            ),
            expected != InboxDesktopNotificationLevel.none,
            reason: 'DM/GM channel=$channel user=$user',
          );
        }
      }
    });

    test('treats mark-unread as an ordinary-all-activity mute gate only', () {
      const InboxUserNotificationSettings user = InboxUserNotificationSettings(
        desktop: InboxDesktopNotificationLevel.all,
      );
      for (final InboxMarkUnread markUnread in InboxMarkUnread.values) {
        final InboxChannelNotificationSettings channel =
            InboxChannelNotificationSettings(
              desktop: InboxDesktopNotificationLevel.all,
              markUnread: markUnread,
            );
        expect(
          resolvesToAllMessagesSubscription(channel: channel, user: user),
          markUnread == InboxMarkUnread.all,
          reason: 'markUnread=$markUnread',
        );
      }

      expect(
        classifyInboxAttention(
          message: '@me',
          username: 'me',
          firstName: '',
          mentionKeys: '',
          firstNameEnabled: false,
          channelMentionsEnabled: false,
          ignoreChannelMentions: false,
          allMessagesSubscription: false,
        ),
        InboxAttentionReason.directMention,
      );
    });

    test('uses the thread matrix with desktop none as a hard gate', () {
      const List<
        ({
          InboxDesktopNotificationLevel threads,
          bool repliesOnly,
          bool mentionsOnly,
          bool expected,
        })
      >
      cases =
          <
            ({
              InboxDesktopNotificationLevel threads,
              bool repliesOnly,
              bool mentionsOnly,
              bool expected,
            })
          >[
            (
              threads: InboxDesktopNotificationLevel.all,
              repliesOnly: true,
              mentionsOnly: false,
              expected: true,
            ),
            (
              threads: InboxDesktopNotificationLevel.all,
              repliesOnly: false,
              mentionsOnly: true,
              expected: false,
            ),
            (
              threads: InboxDesktopNotificationLevel.mention,
              repliesOnly: true,
              mentionsOnly: false,
              expected: false,
            ),
            (
              threads: InboxDesktopNotificationLevel.mention,
              repliesOnly: false,
              mentionsOnly: true,
              expected: true,
            ),
            (
              threads: InboxDesktopNotificationLevel.none,
              repliesOnly: false,
              mentionsOnly: true,
              expected: false,
            ),
            (
              threads: InboxDesktopNotificationLevel.unknown,
              repliesOnly: false,
              mentionsOnly: true,
              expected: true,
            ),
          ];

      for (final (
            :InboxDesktopNotificationLevel threads,
            :bool repliesOnly,
            :bool mentionsOnly,
            :bool expected,
          )
          in cases) {
        expect(
          isFollowedThreadInboxEligible(
            channel: const InboxChannelNotificationSettings(),
            user: InboxUserNotificationSettings(
              desktop: InboxDesktopNotificationLevel.all,
              desktopThreads: threads,
            ),
            unreadReplies: repliesOnly ? 1 : 0,
            unreadMentions: mentionsOnly ? 1 : 0,
          ),
          expected,
          reason: 'desktopThreads=$threads',
        );
      }

      expect(
        isFollowedThreadInboxEligible(
          channel: const InboxChannelNotificationSettings(
            desktop: InboxDesktopNotificationLevel.none,
          ),
          user: const InboxUserNotificationSettings(
            desktop: InboxDesktopNotificationLevel.all,
            desktopThreads: InboxDesktopNotificationLevel.all,
          ),
          unreadReplies: 1,
          unreadMentions: 1,
        ),
        isFalse,
      );
    });
  });

  group('source and precedence matrix', () {
    test('keeps only eligible root sources and deduplicates their IDs', () {
      final List<CanonicalInboxCandidate> result = canonicalizeInboxCandidates(
        InboxSourceSnapshot(
          posts: <InboxPostCandidate>[
            _postCandidate(id: 'channel'),
            _postCandidate(id: 'direct', direct: true),
            _postCandidate(id: 'outgoing', isIncoming: false),
            _postCandidate(id: 'system', isSystem: true),
            _postCandidate(id: 'silent', isSilentNotification: true),
            _postCandidate(id: 'deleted', deleted: true),
            _postCandidate(id: 'reply', rootId: 'thread-root'),
            _postCandidate(id: 'channel'),
          ],
        ),
      );

      expect(
        result.map((CanonicalInboxCandidate item) => item.canonicalId),
        <String>['channel', 'direct'],
      );
      expect(result.first, isA<CanonicalChannelPostCandidate>());
      expect(result.last, isA<CanonicalDirectPostCandidate>());
    });

    test('keeps strongest source reason and lets a thread absorb its root', () {
      final InboxPostCandidate all = _postCandidate(
        id: 'root',
        reason: InboxAttentionReason.allMessagesSubscription,
      );
      final InboxPostCandidate mention = _postCandidate(
        id: 'root',
        reason: InboxAttentionReason.directMention,
      );
      final InboxThreadCandidate thread = _threadCandidate(
        rootId: 'root',
        unreadReplies: 1,
      );

      final List<CanonicalInboxCandidate> postOnly =
          canonicalizeInboxCandidates(
            InboxSourceSnapshot(posts: <InboxPostCandidate>[all, mention]),
          );
      expect(
        (postOnly.single as CanonicalChannelPostCandidate).candidate.reason,
        InboxAttentionReason.directMention,
      );

      final List<CanonicalInboxCandidate> withThread =
          canonicalizeInboxCandidates(
            InboxSourceSnapshot(
              threads: <InboxThreadCandidate>[thread],
              posts: <InboxPostCandidate>[
                mention,
                _postCandidate(id: 'reply', rootId: 'root'),
              ],
            ),
          );
      expect(withThread, hasLength(1));
      expect(withThread.single, isA<CanonicalThreadCandidate>());
    });

    test(
      'orders mention reasons before all activity without parsing a mute',
      () {
        final InboxAttentionReason? reason = classifyInboxAttention(
          message: '@me urgent @channel',
          username: 'me',
          firstName: '',
          mentionKeys: 'urgent',
          firstNameEnabled: false,
          channelMentionsEnabled: true,
          ignoreChannelMentions: false,
          allMessagesSubscription: true,
        );
        expect(reason, InboxAttentionReason.directMention);
      },
    );
  });

  group('post changes and queue exclusivity', () {
    test(
      'edit only changes a known preview and delete removes it idempotently',
      () {
        final InboxPostCandidate original = _postCandidate(
          id: 'post',
          reason: InboxAttentionReason.directMention,
        );
        final InboxSnapshot initial = InboxSnapshot(
          newItems: <InboxItem>[ChannelPostInboxItem(candidate: original)],
        );

        final InboxSnapshot edited = applyInboxPostChange(
          snapshot: initial,
          postId: 'post',
          candidate: _postCandidate(
            id: 'post',
            message: 'edited',
            reason: InboxAttentionReason.allMessagesSubscription,
          ),
          kind: InboxPostChangeKind.edited,
        );
        final ChannelPostInboxItem item =
            edited.newItems.single as ChannelPostInboxItem;
        expect(item.post.message, 'edited');
        expect(item.candidate.reason, InboxAttentionReason.directMention);

        final InboxSnapshot deleted = applyInboxPostChange(
          snapshot: edited,
          postId: 'post',
          candidate: null,
          kind: InboxPostChangeKind.deleted,
        );
        expect(deleted.newItems, isEmpty);
        expect(
          applyInboxPostChange(
            snapshot: deleted,
            postId: 'post',
            candidate: null,
            kind: InboxPostChangeKind.deleted,
          ).newItems,
          isEmpty,
        );
      },
    );

    test(
      'suppresses postponed post IDs but reactivates an explicit thread mention',
      () {
        final InboxPostCandidate first = _postCandidate(
          id: 'first',
          direct: true,
        );
        final InboxPostCandidate second = _postCandidate(
          id: 'second',
          direct: true,
        );
        final DirectMessageBundleInboxItem newBundle =
            DirectMessageBundleInboxItem(
              channelId: 'dm',
              authorId: 'other',
              automationClass: InboxAutomationClass.person,
              messages: <InboxPostCandidate>[first, second],
            );
        final ThreadInboxItem postponedThread = ThreadInboxItem(
          thread: _threadCandidate(rootId: 'root', unreadReplies: 1).thread,
          channel: _channel,
          teamId: 'team',
          postponedAt: DateTime.utc(2026),
        );
        final ThreadInboxItem ordinaryThread = ThreadInboxItem(
          thread: _threadCandidate(rootId: 'root', unreadReplies: 2).thread,
          channel: _channel,
          teamId: 'team',
        );

        final InboxSnapshot suppressed = reconcileQueues(
          newItems: <InboxItem>[newBundle, ordinaryThread],
          postponedItems: <InboxItem>[
            ChannelPostInboxItem(candidate: first),
            postponedThread,
          ],
        );
        expect(
          (suppressed.newItems.single as DirectMessageBundleInboxItem).postIds,
          <String>['second'],
        );
        expect(suppressed.postponedItems, hasLength(2));

        final InboxSnapshot reactivated = reconcileQueues(
          newItems: <InboxItem>[
            ThreadInboxItem(
              thread: ordinaryThread.thread,
              channel: _channel,
              teamId: 'team',
              reactivatesPostponed: true,
            ),
          ],
          postponedItems: <InboxItem>[postponedThread],
        );
        expect(reactivated.newItems.single.key, 'thread:root');
        expect(reactivated.postponedItems, isEmpty);
      },
    );
  });
}

InboxDesktopNotificationLevel _effectiveDesktop({
  required InboxDesktopNotificationLevel channel,
  required InboxDesktopNotificationLevel user,
}) => switch (channel) {
  InboxDesktopNotificationLevel.all ||
  InboxDesktopNotificationLevel.mention ||
  InboxDesktopNotificationLevel.none => channel,
  InboxDesktopNotificationLevel.inherit => switch (user) {
    InboxDesktopNotificationLevel.all ||
    InboxDesktopNotificationLevel.mention ||
    InboxDesktopNotificationLevel.none => user,
    InboxDesktopNotificationLevel.inherit ||
    InboxDesktopNotificationLevel.unknown =>
      InboxDesktopNotificationLevel.mention,
  },
  InboxDesktopNotificationLevel.unknown =>
    InboxDesktopNotificationLevel.mention,
};

const SidebarChannel _channel = SidebarChannel(
  id: 'channel',
  teamId: 'team',
  name: 'channel',
  displayName: 'Channel',
  kind: ChannelKind.publicChannel,
);

InboxPostCandidate _postCandidate({
  required String id,
  bool direct = false,
  String rootId = '',
  String message = 'message',
  InboxAttentionReason reason = InboxAttentionReason.directMention,
  bool isIncoming = true,
  bool isSystem = false,
  bool isSilentNotification = false,
  bool deleted = false,
}) => InboxPostCandidate(
  post: Post(
    id: id,
    channelId: direct ? 'dm' : _channel.id,
    author: const PostAuthor(id: 'other', displayName: 'Other'),
    sentAt: DateTime.utc(2026, 9, 27),
    message: message,
    rootId: rootId,
    isDeleted: deleted,
  ),
  channel: direct
      ? const SidebarChannel(
          id: 'dm',
          teamId: 'team',
          name: 'dm',
          displayName: 'DM',
          kind: ChannelKind.directMessage,
        )
      : _channel,
  reason: reason,
  isIncoming: isIncoming,
  isSystem: isSystem,
  isSilentNotification: isSilentNotification,
);

InboxThreadCandidate _threadCandidate({
  required String rootId,
  required int unreadReplies,
}) => InboxThreadCandidate(
  thread: FollowedThread(
    root: Post(
      id: rootId,
      channelId: _channel.id,
      author: const PostAuthor(id: 'other', displayName: 'Other'),
      sentAt: DateTime.utc(2026, 9, 27),
      message: 'root',
    ),
    replyCount: unreadReplies,
    lastReplyAt: DateTime.utc(2026, 9, 27, 1, unreadReplies),
    lastViewedAt: DateTime.utc(2026, 9, 27),
    unreadReplies: unreadReplies,
    unreadMentions: 0,
  ),
  channel: _channel,
  teamId: 'team',
);
