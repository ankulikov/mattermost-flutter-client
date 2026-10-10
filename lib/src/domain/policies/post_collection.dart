import 'package:mattermost_flutter/src/domain/models/page.dart';
import 'package:mattermost_flutter/src/domain/models/post.dart';

List<Post> mergePosts(List<Post> current, List<Post> incoming) {
  final Map<String, Post> byId = <String, Post>{
    for (final Post post in current) post.id: post,
  };
  for (final Post post in incoming) {
    final Post? existing = byId[post.id];
    if (existing == null) {
      byId[post.id] = post;
      continue;
    }
    final Post canonical = existing.revisionAt.isAfter(post.revisionAt)
        ? existing
        : post;
    byId[post.id] = canonical.withThreadSummary(
      replyCount: existing.replyCount > post.replyCount
          ? existing.replyCount
          : post.replyCount,
      lastReplyAt: _latest(existing.lastReplyAt, post.lastReplyAt),
    );
  }
  final List<Post> result = byId.values.toList(growable: false)
    ..sort((Post a, Post b) {
      final int byDate = a.sentAt.compareTo(b.sentAt);
      return byDate == 0 ? a.id.compareTo(b.id) : byDate;
    });
  return List<Post>.unmodifiable(result);
}

Map<String, ChannelReplySummary> mergeReplySummaries(
  Map<String, ChannelReplySummary> current,
  Map<String, ChannelReplySummary> incoming,
) {
  final Set<String> rootIds = <String>{...current.keys, ...incoming.keys};
  return Map<String, ChannelReplySummary>.unmodifiable(
    <String, ChannelReplySummary>{
      for (final String rootId in rootIds)
        rootId: ChannelReplySummary(
          replyIds: Set<String>.unmodifiable(<String>{
            ...?current[rootId]?.replyIds,
            ...?incoming[rootId]?.replyIds,
          }),
          lastReplyAt: _latest(
            current[rootId]?.lastReplyAt,
            incoming[rootId]?.lastReplyAt,
          ),
        ),
    },
  );
}

List<Post> applyReplySummaries(
  List<Post> posts,
  Map<String, ChannelReplySummary> summaries,
) => List<Post>.unmodifiable(
  posts.map((Post post) {
    final ChannelReplySummary? summary = summaries[post.id];
    if (summary == null) return post;
    final int observedCount = summary.replyIds.length;
    return post.withThreadSummary(
      replyCount: post.replyCount > observedCount
          ? post.replyCount
          : observedCount,
      lastReplyAt: _latest(post.lastReplyAt, summary.lastReplyAt),
    );
  }),
);

DateTime? _latest(DateTime? first, DateTime? second) {
  if (first == null) return second;
  if (second == null) return first;
  return first.isAfter(second) ? first : second;
}
