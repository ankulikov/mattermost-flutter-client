import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_post_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_thread_change.dart';

void main() {
  test('upserts a hydrated reply and thread update as one thread', () {
    InboxSnapshot snapshot = InboxSnapshot();
    for (final InboxThreadUpdated event in <InboxThreadUpdated>[
      InboxThreadUpdated(
        sequence: 1,
        rootPostId: 'root',
        candidate: _candidate(unreadReplies: 1),
      ),
      InboxThreadUpdated(
        sequence: 2,
        rootPostId: 'root',
        candidate: _candidate(unreadReplies: 3),
      ),
    ]) {
      snapshot = applyInboxThreadChange(
        snapshot: snapshot,
        event: event,
      ).snapshot;
    }

    expect(snapshot.newItems, hasLength(1));
    final ThreadInboxItem item = snapshot.newItems.single as ThreadInboxItem;
    expect(item.key, 'thread:root');
    expect(item.thread.unreadReplies, 3);
  });

  test('is idempotent whichever reply and aggregate event arrives first', () {
    for (final List<InboxThreadUpdated> ordering in <List<InboxThreadUpdated>>[
      <InboxThreadUpdated>[
        InboxThreadUpdated(
          sequence: 1,
          rootPostId: 'root',
          candidate: _candidate(unreadReplies: 1),
        ),
        InboxThreadUpdated(
          sequence: 2,
          rootPostId: 'root',
          candidate: _candidate(unreadReplies: 2),
        ),
      ],
      <InboxThreadUpdated>[
        InboxThreadUpdated(
          sequence: 1,
          rootPostId: 'root',
          candidate: _candidate(unreadReplies: 2),
        ),
        InboxThreadUpdated(
          sequence: 2,
          rootPostId: 'root',
          candidate: _candidate(unreadReplies: 1),
        ),
      ],
    ]) {
      InboxSnapshot snapshot = InboxSnapshot();
      for (final InboxThreadUpdated event in ordering) {
        snapshot = applyInboxThreadChange(
          snapshot: snapshot,
          event: event,
        ).snapshot;
      }
      expect(snapshot.newItems.whereType<ThreadInboxItem>(), hasLength(1));
      expect(snapshot.newItems.single.key, 'thread:root');
    }
  });

  test('removes ineligible, unfollowed, read, and deleted thread roots', () {
    final InboxSnapshot initial = InboxSnapshot(
      newItems: <InboxItem>[
        ThreadInboxItem(
          thread: _candidate(unreadReplies: 2).thread,
          channel: _channel,
          teamId: 'team',
        ),
      ],
    );
    final InboxSnapshot ineligible = applyInboxThreadChange(
      snapshot: initial,
      event: const InboxThreadUpdated(
        sequence: 1,
        rootPostId: 'root',
        isInboxEligible: false,
      ),
    ).snapshot;
    expect(ineligible.newItems, isEmpty);

    final InboxSnapshot unfollowed = applyInboxThreadChange(
      snapshot: initial,
      event: const InboxThreadFollowChanged(
        sequence: 2,
        rootPostId: 'root',
        isFollowing: false,
      ),
    ).snapshot;
    expect(unfollowed.newItems, isEmpty);

    final InboxSnapshot read = applyInboxThreadChange(
      snapshot: initial,
      event: const InboxThreadReadChanged(sequence: 3, rootPostId: 'root'),
    ).snapshot;
    expect(read.newItems, isEmpty);

    final InboxSnapshot deleted = applyInboxPostChange(
      snapshot: initial,
      postId: 'root',
      candidate: null,
      kind: InboxPostChangeKind.deleted,
    );
    expect(deleted.newItems, isEmpty);
  });

  test('preserves a known thread while incomplete data requests recovery', () {
    final InboxSnapshot initial = InboxSnapshot(
      newItems: <InboxItem>[
        ThreadInboxItem(
          thread: _candidate(unreadReplies: 2).thread,
          channel: _channel,
          teamId: 'team',
        ),
      ],
    );

    final InboxThreadChangeResult result = applyInboxThreadChange(
      snapshot: initial,
      event: const InboxThreadUpdated(
        sequence: 1,
        rootPostId: 'root',
        recoveryRequired: true,
      ),
    );

    expect(result.recoveryRequired, isTrue);
    expect(result.snapshot.newItems.single.key, 'thread:root');
  });

  test('preserves postponed exclusivity until an explicit reactivation', () {
    final ThreadInboxItem postponed = ThreadInboxItem(
      thread: _candidate(unreadReplies: 1).thread,
      channel: _channel,
      teamId: 'team',
      postponedAt: DateTime.utc(2026),
    );
    final InboxSnapshot initial = InboxSnapshot(
      postponedItems: <InboxItem>[postponed],
    );

    final InboxSnapshot suppressed = applyInboxThreadChange(
      snapshot: initial,
      event: InboxThreadUpdated(
        sequence: 1,
        rootPostId: 'root',
        candidate: _candidate(unreadReplies: 2),
      ),
    ).snapshot;
    expect(suppressed.newItems, isEmpty);
    expect(suppressed.postponedItems.single.key, 'thread:root');

    final InboxSnapshot reactivated = applyInboxThreadChange(
      snapshot: initial,
      event: InboxThreadUpdated(
        sequence: 2,
        rootPostId: 'root',
        candidate: _candidate(unreadReplies: 2, explicitMention: true),
        reactivatePostponed: true,
      ),
    ).snapshot;
    expect(reactivated.newItems.single.key, 'thread:root');
    expect(reactivated.postponedItems, isEmpty);
  });
}

const SidebarChannel _channel = SidebarChannel(
  id: 'channel',
  teamId: 'team',
  name: 'channel',
  displayName: 'Channel',
  kind: ChannelKind.publicChannel,
);

InboxThreadCandidate _candidate({
  required int unreadReplies,
  bool explicitMention = false,
}) => InboxThreadCandidate(
  channel: _channel,
  teamId: 'team',
  hasNewExplicitMention: explicitMention,
  thread: FollowedThread(
    root: Post(
      id: 'root',
      channelId: 'channel',
      author: const PostAuthor(id: 'other', displayName: 'Other'),
      sentAt: DateTime.utc(2026, 1, 1),
      message: 'Root',
    ),
    replyCount: unreadReplies,
    lastReplyAt: DateTime.utc(2026, 1, 1, 0, unreadReplies),
    lastViewedAt: DateTime.utc(2025),
    unreadReplies: unreadReplies,
    unreadMentions: explicitMention ? 1 : 0,
  ),
);
