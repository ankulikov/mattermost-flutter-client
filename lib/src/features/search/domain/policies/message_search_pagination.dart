import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';

MessageSearchPage mergeMessageSearchPages({
  required MessageSearchPage current,
  required MessageSearchPage incoming,
}) {
  final Set<String> existingIds = current.results
      .map((MessageSearchResult result) => result.post.id)
      .toSet();
  final List<MessageSearchResult> additions = incoming.results
      .where((MessageSearchResult result) => existingIds.add(result.post.id))
      .toList(growable: false);
  final bool repeated = current.fingerprint == incoming.fingerprint;
  return MessageSearchPage(
    results: List<MessageSearchResult>.unmodifiable(<MessageSearchResult>[
      ...current.results,
      ...additions,
    ]),
    page: incoming.page,
    hasMore: !repeated && additions.isNotEmpty && incoming.hasMore,
    fingerprint: incoming.fingerprint,
  );
}
