import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/page.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';
import 'package:mattermost_flutter/src/domain/policies/post_collection.dart';

void main() {
  test('merges post pages by id and preserves the stronger thread summary', () {
    final Post older = _post('post-1', 1, replies: 3);
    final Post newer = _post('post-1', 1, replies: 1);
    final List<Post> merged = mergePosts(<Post>[older], <Post>[newer]);

    expect(merged, hasLength(1));
    expect(merged.single.replyCount, 3);
  });

  test('merges observed replies and projects them to their root post', () {
    final Map<String, ChannelReplySummary> summaries = mergeReplySummaries(
      <String, ChannelReplySummary>{
        'root': ChannelReplySummary(replyIds: <String>{'reply-1'}),
      },
      <String, ChannelReplySummary>{
        'root': ChannelReplySummary(replyIds: <String>{'reply-2'}),
      },
    );

    final List<Post> projected = applyReplySummaries(<Post>[
      _post('root', 1),
    ], summaries);
    expect(projected.single.replyCount, 2);
  });
}

Post _post(String id, int second, {int replies = 0}) => Post(
  id: id,
  channelId: 'channel',
  author: const PostAuthor(id: 'user', displayName: 'User'),
  sentAt: DateTime(2026, 1, 1, 0, 0, second),
  message: id,
  replyCount: replies,
);
