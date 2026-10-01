import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/apply_inbox_post_change.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/canonicalize_inbox_candidates.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/classify_inbox_section.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/group_direct_messages.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/policies/reconcile_queues.dart';

void main() {
  group('applyInboxPostChange', () {
    test('deduplicates and regroups realtime direct messages', () {
      final InboxPostCandidate first = _postCandidate(
        id: 'first',
        direct: true,
        at: DateTime.utc(2026, 9, 4, 12),
      );
      final InboxPostCandidate second = _postCandidate(
        id: 'second',
        direct: true,
        at: DateTime.utc(2026, 9, 4, 12, 1),
      );
      final InboxSnapshot initial = InboxSnapshot(
        newItems: <InboxItem>[
          DirectMessageBundleInboxItem(
            channelId: 'dm',
            authorId: 'other',
            automationClass: InboxAutomationClass.person,
            messages: <InboxPostCandidate>[first],
          ),
        ],
      );

      final InboxSnapshot added = applyInboxPostChange(
        snapshot: initial,
        postId: second.post.id,
        candidate: second,
      );
      final InboxSnapshot duplicated = applyInboxPostChange(
        snapshot: added,
        postId: second.post.id,
        candidate: second,
      );

      expect(duplicated.newItems, hasLength(1));
      expect(duplicated.newItems.single.postIds, <String>['first', 'second']);
    });

    test('removes a deleted post but keeps postponed exclusivity', () {
      final InboxPostCandidate first = _postCandidate(id: 'first');
      final InboxPostCandidate postponed = _postCandidate(id: 'postponed');
      final InboxSnapshot result = applyInboxPostChange(
        snapshot: InboxSnapshot(
          newItems: <InboxItem>[ChannelPostInboxItem(candidate: first)],
          postponedItems: <InboxItem>[
            ChannelPostInboxItem(candidate: postponed),
          ],
        ),
        postId: first.post.id,
        candidate: null,
      );

      expect(result.newItems, isEmpty);
      expect(result.postponedItems.single.postIds, <String>['postponed']);
    });
  });

  group('classifyInboxSection', () {
    test('classifies channel mentions and automation messages', () {
      expect(
        classifyInboxSection(
          ChannelPostInboxItem(candidate: _postCandidate(id: 'mention')),
        ),
        InboxSection.mentions,
      );
      expect(
        classifyInboxSection(
          ChannelPostInboxItem(
            candidate: _postCandidate(id: 'bot', fromWebhook: true),
          ),
        ),
        InboxSection.botsAndIntegrations,
      );
    });

    test('classifies group mentions into their own section', () {
      expect(
        classifyInboxSection(
          ChannelPostInboxItem(
            candidate: _postCandidate(
              id: 'group-mention',
              reason: InboxAttentionReason.groupMention,
            ),
          ),
        ),
        InboxSection.groupMentions,
      );
      expect(
        classifyInboxSection(
          ThreadInboxItem(
            thread: _thread(rootId: 'group-root'),
            channel: _channel(),
            teamId: 'team',
            rootAttentionReason: InboxAttentionReason.groupMention,
          ),
        ),
        InboxSection.groupMentions,
      );
    });

    test('classifies person direct messages as Direct Messages', () {
      expect(
        classifyInboxSection(
          DirectMessageBundleInboxItem(
            channelId: 'dm',
            authorId: 'other',
            automationClass: InboxAutomationClass.person,
            messages: <InboxPostCandidate>[
              _postCandidate(id: 'dm', direct: true),
            ],
          ),
        ),
        InboxSection.directMessages,
      );
    });

    test('keeps a thread rooted in a mention in Mentions', () {
      expect(
        classifyInboxSection(
          ThreadInboxItem(
            thread: _thread(rootId: 'root'),
            channel: _channel(),
            teamId: 'team',
            rootAttentionReason: InboxAttentionReason.directMention,
          ),
        ),
        InboxSection.mentions,
      );
    });

    test('keeps a thread rooted in a direct message in Direct Messages', () {
      expect(
        classifyInboxSection(
          ThreadInboxItem(
            thread: _thread(rootId: 'root'),
            channel: _channel(direct: true),
            teamId: 'team',
          ),
        ),
        InboxSection.directMessages,
      );
    });

    test('a new mention inside any thread takes Threads precedence', () {
      expect(
        classifyInboxSection(
          ThreadInboxItem(
            thread: _thread(rootId: 'root', unreadMentions: 1),
            channel: _channel(direct: true),
            teamId: 'team',
            rootAttentionReason: InboxAttentionReason.directMention,
          ),
        ),
        InboxSection.threads,
      );
    });
  });

  group('canonicalizeInboxCandidates', () {
    test('deduplicates repeated post delivery by post ID', () {
      final InboxPostCandidate repeated = _postCandidate(id: 'post-1');

      final List<CanonicalInboxCandidate> result = canonicalizeInboxCandidates(
        InboxSourceSnapshot(posts: <InboxPostCandidate>[repeated, repeated]),
      );

      expect(result, hasLength(1));
      expect(result.single, isA<CanonicalChannelPostCandidate>());
    });

    test('gives a followed thread precedence over its root and replies', () {
      final FollowedThread thread = _thread(rootId: 'root');
      final List<CanonicalInboxCandidate> result = canonicalizeInboxCandidates(
        InboxSourceSnapshot(
          threads: <InboxThreadCandidate>[
            InboxThreadCandidate(
              thread: thread,
              channel: _channel(),
              teamId: 'team',
            ),
          ],
          posts: <InboxPostCandidate>[
            _postCandidate(id: 'root'),
            _postCandidate(id: 'reply', rootId: 'root'),
          ],
        ),
      );

      expect(result, hasLength(1));
      expect(result.single, isA<CanonicalThreadCandidate>());
    });

    test('keeps the stronger reason for duplicate post sources', () {
      final List<CanonicalInboxCandidate> result = canonicalizeInboxCandidates(
        InboxSourceSnapshot(
          posts: <InboxPostCandidate>[
            _postCandidate(
              id: 'post-1',
              reason: InboxAttentionReason.allMessagesSubscription,
            ),
            _postCandidate(
              id: 'post-1',
              reason: InboxAttentionReason.directMention,
            ),
          ],
        ),
      );

      final CanonicalChannelPostCandidate item =
          result.single as CanonicalChannelPostCandidate;
      expect(item.candidate.reason, InboxAttentionReason.directMention);
    });
  });

  group('groupDirectMessages', () {
    test('groups messages from one sender regardless of time gap', () {
      final DateTime start = DateTime.utc(2026);
      final List<InboxItem> items =
          groupDirectMessages(<CanonicalInboxCandidate>[
            CanonicalDirectPostCandidate(
              _postCandidate(id: 'one', direct: true, at: start),
            ),
            CanonicalDirectPostCandidate(
              _postCandidate(
                id: 'two',
                direct: true,
                at: start.add(const Duration(days: 3)),
              ),
            ),
          ]);

      expect(items, hasLength(1));
      expect(items.single.postIds, <String>['one', 'two']);
    });

    test('keeps direct messages from different senders separate', () {
      final List<InboxItem> items =
          groupDirectMessages(<CanonicalInboxCandidate>[
            CanonicalDirectPostCandidate(
              _postCandidate(id: 'ada', direct: true, authorId: 'ada'),
            ),
            CanonicalDirectPostCandidate(
              _postCandidate(id: 'grace', direct: true, authorId: 'grace'),
            ),
          ]);

      expect(items, hasLength(2));
    });

    test('does not group people with automation messages', () {
      final DateTime start = DateTime.utc(2026);
      final List<InboxItem> items =
          groupDirectMessages(<CanonicalInboxCandidate>[
            CanonicalDirectPostCandidate(
              _postCandidate(id: 'person', direct: true, at: start),
            ),
            CanonicalDirectPostCandidate(
              _postCandidate(
                id: 'bot',
                direct: true,
                at: start.add(const Duration(seconds: 1)),
                fromWebhook: true,
              ),
            ),
          ]);

      expect(items, hasLength(2));
      expect(
        items.map(
          (InboxItem item) =>
              (item as DirectMessageBundleInboxItem).automationClass,
        ),
        <InboxAutomationClass>[
          InboxAutomationClass.person,
          InboxAutomationClass.automation,
        ],
      );
    });
  });

  group('reconcileQueues', () {
    test('sorts every item by its latest event date, newest first', () {
      final DateTime start = DateTime.utc(2026);
      final FollowedThread baseThread = _thread(rootId: 'thread');
      final InboxSnapshot result = reconcileQueues(
        newItems: <InboxItem>[
          ChannelPostInboxItem(
            candidate: _postCandidate(id: 'channel', at: start),
          ),
          DirectMessageBundleInboxItem(
            channelId: 'dm',
            authorId: 'other',
            automationClass: InboxAutomationClass.person,
            messages: <InboxPostCandidate>[
              _postCandidate(id: 'dm-one', direct: true, at: start),
              _postCandidate(
                id: 'dm-two',
                direct: true,
                at: start.add(const Duration(days: 1)),
              ),
            ],
          ),
          ThreadInboxItem(
            thread: FollowedThread(
              root: baseThread.root,
              replyCount: baseThread.replyCount,
              lastReplyAt: start.add(const Duration(days: 2)),
              lastViewedAt: baseThread.lastViewedAt,
              unreadReplies: baseThread.unreadReplies,
              unreadMentions: baseThread.unreadMentions,
            ),
            channel: _channel(),
            teamId: 'team',
          ),
        ],
        postponedItems: const <InboxItem>[],
      );

      expect(result.newItems.map((InboxItem item) => item.key), <String>[
        'thread:thread',
        'direct:dm:dm-one',
        'post:channel',
      ]);
    });

    test('suppresses postponed post IDs from New bundles', () {
      final DateTime at = DateTime.utc(2026);
      final DirectMessageBundleInboxItem newBundle =
          DirectMessageBundleInboxItem(
            channelId: 'dm',
            authorId: 'other',
            automationClass: InboxAutomationClass.person,
            messages: <InboxPostCandidate>[
              _postCandidate(id: 'first', direct: true, at: at),
              _postCandidate(
                id: 'second',
                direct: true,
                at: at.add(const Duration(minutes: 1)),
              ),
            ],
          );
      final ChannelPostInboxItem postponed = ChannelPostInboxItem(
        candidate: _postCandidate(id: 'first'),
      );

      final InboxSnapshot result = reconcileQueues(
        newItems: <InboxItem>[newBundle],
        postponedItems: <InboxItem>[postponed],
      );

      expect(
        (result.newItems.single as DirectMessageBundleInboxItem).postIds,
        <String>['second'],
      );
      expect(result.postponedItems, <InboxItem>[postponed]);
    });

    test('reactivates a postponed thread on a new explicit mention', () {
      final FollowedThread thread = _thread(rootId: 'root');
      final InboxSnapshot result = reconcileQueues(
        newItems: <InboxItem>[
          ThreadInboxItem(
            thread: thread,
            channel: _channel(),
            teamId: 'team',
            reactivatesPostponed: true,
          ),
        ],
        postponedItems: <InboxItem>[
          ThreadInboxItem(thread: thread, channel: _channel(), teamId: 'team'),
        ],
      );

      expect(result.newItems, hasLength(1));
      expect(result.postponedItems, isEmpty);
    });
  });
}

InboxPostCandidate _postCandidate({
  required String id,
  String rootId = '',
  bool direct = false,
  String authorId = 'other',
  DateTime? at,
  InboxAttentionReason reason = InboxAttentionReason.directMention,
  bool fromWebhook = false,
}) => InboxPostCandidate(
  post: Post(
    id: id,
    channelId: direct ? 'dm' : 'channel',
    author: PostAuthor(id: authorId, displayName: authorId),
    sentAt: at ?? DateTime.utc(2026),
    message: id,
    rootId: rootId,
  ),
  channel: SidebarChannel(
    id: direct ? 'dm' : 'channel',
    teamId: 'team',
    name: 'name',
    displayName: 'name',
    kind: direct ? ChannelKind.directMessage : ChannelKind.publicChannel,
  ),
  reason: reason,
  isFromWebhook: fromWebhook,
);

FollowedThread _thread({required String rootId, int unreadMentions = 0}) {
  final DateTime at = DateTime.utc(2026);
  return FollowedThread(
    root: Post(
      id: rootId,
      channelId: 'channel',
      author: const PostAuthor(id: 'other', displayName: 'Other'),
      sentAt: at,
      message: 'root',
    ),
    replyCount: 1,
    lastReplyAt: at,
    lastViewedAt: at.subtract(const Duration(minutes: 1)),
    unreadReplies: 1,
    unreadMentions: unreadMentions,
  );
}

SidebarChannel _channel({bool direct = false}) => SidebarChannel(
  id: direct ? 'dm' : 'channel',
  teamId: 'team',
  name: 'name',
  displayName: 'name',
  kind: direct ? ChannelKind.directMessage : ChannelKind.publicChannel,
);
