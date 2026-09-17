import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';

/// Reproduces the official client's group ordering without membership bias.
///
/// The current user's group memberships are deliberately not an input. The
/// canonical handle is preferred when it starts with the query, then matching
/// display-name prefixes, with the handle providing a deterministic tie-break.
List<GroupMentionCandidate> rankGroupMentionCandidates(
  Iterable<GroupMentionCandidate> candidates,
  String term,
) {
  final String query = _normalize(term);
  final List<GroupMentionCandidate> result = List<GroupMentionCandidate>.of(
    candidates,
  );
  result.sort((GroupMentionCandidate left, GroupMentionCandidate right) {
    final int rank = _matchRank(
      left,
      query,
    ).compareTo(_matchRank(right, query));
    if (rank != 0) return rank;
    final int name = _normalize(
      left.group.name,
    ).compareTo(_normalize(right.group.name));
    if (name != 0) return name;
    return left.group.id.compareTo(right.group.id);
  });
  return List<GroupMentionCandidate>.unmodifiable(result);
}

int _matchRank(GroupMentionCandidate candidate, String query) {
  if (query.isEmpty) return 3;
  final String name = _normalize(candidate.group.name);
  if (name == query) return 0;
  if (name.startsWith(query)) return 1;
  final String displayName = _normalize(candidate.group.displayName);
  if (displayName.startsWith(query) ||
      displayName
          .split(RegExp(r'\s+'))
          .any((String part) => part.startsWith(query))) {
    return 2;
  }
  return 3;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[\u0300-\u036f]'), '');
