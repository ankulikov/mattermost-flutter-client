import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/channel.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/models/thread.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/canonical_inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_candidate.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_item.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_realtime_event.dart';
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

    test(
      'edits an existing preview without changing its membership reason',
      () {
        final InboxPostCandidate original = _postCandidate(
          id: 'post',
          direct: true,
          reason: InboxAttentionReason.directMention,
        );
        final InboxPostCandidate editedWirePreview = _postCandidate(
          id: 'post',
          direct: false,
          authorId: 'different-author',
          message: 'edited preview',
          reason: InboxAttentionReason.allMessagesSubscription,
        );
        final InboxSnapshot result = applyInboxPostChange(
          snapshot: InboxSnapshot(
            newItems: <InboxItem>[
              DirectMessageBundleInboxItem(
                channelId: 'dm',
                authorId: 'other',
                automationClass: InboxAutomationClass.person,
                messages: <InboxPostCandidate>[original],
              ),
            ],
          ),
          postId: 'post',
          candidate: editedWirePreview,
          kind: InboxPostChangeKind.edited,
        );

        final InboxPostCandidate retained =
            (result.newItems.single as DirectMessageBundleInboxItem)
                .messages
                .single;
        expect(retained.post.message, editedWirePreview.post.message);
        expect(retained.reason, InboxAttentionReason.directMention);
        expect(retained.channel.id, 'dm');
        expect(retained.post.author.id, 'different-author');
      },
    );

    test('does not create an unknown item from an edit', () {
      final InboxSnapshot result = applyInboxPostChange(
        snapshot: InboxSnapshot(),
        postId: 'unknown',
        candidate: _postCandidate(id: 'unknown'),
        kind: InboxPostChangeKind.edited,
      );

      expect(result.newItems, isEmpty);
    });

    test('deletes one direct message from a bundle idempotently', () {
      final InboxPostCandidate first = _postCandidate(
        id: 'first',
        direct: true,
      );
      final InboxPostCandidate second = _postCandidate(
        id: 'second',
        direct: true,
      );
      final InboxSnapshot initial = InboxSnapshot(
        newItems: <InboxItem>[
          DirectMessageBundleInboxItem(
            channelId: 'dm',
            authorId: 'other',
            automationClass: InboxAutomationClass.person,
            messages: <InboxPostCandidate>[first, second],
          ),
        ],
      );

      final InboxSnapshot deleted = applyInboxPostChange(
        snapshot: initial,
        postId: 'first',
        candidate: null,
        kind: InboxPostChangeKind.deleted,
      );
      final InboxSnapshot duplicate = applyInboxPostChange(
        snapshot: deleted,
        postId: 'first',
        candidate: null,
        kind: InboxPostChangeKind.deleted,
      );

      expect(deleted.newItems.single.postIds, <String>['second']);
      expect(duplicate.newItems.single.postIds, <String>['second']);
    });

    test('deletes a followed root item', () {
      final InboxSnapshot result = applyInboxPostChange(
        snapshot: InboxSnapshot(
          newItems: <InboxItem>[
            ThreadInboxItem(
              thread: _thread(rootId: 'root'),
              channel: _channel(),
              teamId: 'team',
            ),
          ],
        ),
        postId: 'root',
        candidate: null,
        kind: InboxPostChangeKind.deleted,
      );

      expect(result.newItems, isEmpty);
    });
  });

  group('classifyInboxSection', () {
    test('keeps ordinary channel activity separate from mentions', () {
      expect(
        classifyInboxSection(
          ChannelPostInboxItem(candidate: _postCandidate(id: 'mention')),
        ),
        InboxSection.mentions,
      );
      expect(
        classifyInboxSection(
          ChannelPostInboxItem(
            candidate: _postCandidate(
              id: 'ordinary',
              reason: InboxAttentionReason.allMessagesSubscription,
            ),
          ),
        ),
        InboxSection.allActivity,
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
    test('groups adjacent messages up to the inclusive two-minute bound', () {
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
                at: start.add(
                  defaultDirectMessageGroupingWindow -
                      const Duration(milliseconds: 1),
                ),
              ),
            ),
            CanonicalDirectPostCandidate(
              _postCandidate(
                id: 'three',
                direct: true,
                at: start.add(defaultDirectMessageGroupingWindow),
              ),
            ),
          ]);

      expect(items, hasLength(1));
      expect(items.single.postIds, <String>['one', 'two', 'three']);
    });

    test('starts a new bundle after a gap beyond the window', () {
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
                at: start.add(
                  defaultDirectMessageGroupingWindow +
                      const Duration(milliseconds: 1),
                ),
              ),
            ),
          ]);

      expect(items.map((InboxItem item) => item.postIds), <List<String>>[
        <String>['one'],
        <String>['two'],
      ]);
    });

    test('breaks a bundle at an intervening direct author', () {
      final DateTime start = DateTime.utc(2026);
      final List<InboxItem> items =
          groupDirectMessages(<CanonicalInboxCandidate>[
            CanonicalDirectPostCandidate(
              _postCandidate(
                id: 'first-ada',
                direct: true,
                authorId: 'ada',
                at: start,
              ),
            ),
            CanonicalDirectPostCandidate(
              _postCandidate(
                id: 'grace',
                direct: true,
                authorId: 'grace',
                at: start.add(const Duration(seconds: 10)),
              ),
            ),
            CanonicalDirectPostCandidate(
              _postCandidate(
                id: 'second-ada',
                direct: true,
                authorId: 'ada',
                at: start.add(const Duration(seconds: 20)),
              ),
            ),
          ]);

      expect(items.map((InboxItem item) => item.postIds), <List<String>>[
        <String>['first-ada'],
        <String>['grace'],
        <String>['second-ada'],
      ]);
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

    test('is deterministic for batched and reordered realtime input', () {
      final DateTime start = DateTime.utc(2026);
      final List<CanonicalInboxCandidate> batch = <CanonicalInboxCandidate>[
        CanonicalDirectPostCandidate(
          _postCandidate(
            id: 'second',
            direct: true,
            at: start.add(const Duration(seconds: 60)),
          ),
        ),
        CanonicalDirectPostCandidate(
          _postCandidate(id: 'first', direct: true, at: start),
        ),
        CanonicalDirectPostCandidate(
          _postCandidate(
            id: 'other-channel',
            direct: true,
            at: start.add(const Duration(seconds: 90)),
            channelId: 'other-dm',
          ),
        ),
      ];

      final List<InboxItem> forward = groupDirectMessages(batch);
      final List<InboxItem> reversed = groupDirectMessages(batch.reversed);

      expect(
        forward.map((InboxItem item) => item.key),
        reversed.map((InboxItem item) => item.key),
      );
      expect(
        forward.map((InboxItem item) => item.postIds),
        reversed.map((InboxItem item) => item.postIds),
      );
      expect(forward.expand((InboxItem item) => item.postIds).toSet(), <String>{
        'first',
        'second',
        'other-channel',
      });
      expect(
        forward.fold<int>(
          0,
          (int count, InboxItem item) => count + item.postIds.length,
        ),
        3,
      );
    });
  });

  group('reconcileQueues', () {
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
  String? message,
  DateTime? at,
  String? channelId,
  InboxAttentionReason reason = InboxAttentionReason.directMention,
  bool fromWebhook = false,
}) => InboxPostCandidate(
  post: Post(
    id: id,
    channelId: channelId ?? (direct ? 'dm' : 'channel'),
    author: PostAuthor(id: authorId, displayName: authorId),
    sentAt: at ?? DateTime.utc(2026),
    message: message ?? id,
    rootId: rootId,
  ),
  channel: SidebarChannel(
    id: channelId ?? (direct ? 'dm' : 'channel'),
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
