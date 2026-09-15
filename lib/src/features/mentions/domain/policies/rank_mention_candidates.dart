import 'package:mattermost_flutter/src/features/mentions/domain/models/mention_candidate.dart';

/// Applies stable client-side ordering to each server membership section.
///
/// The server term is deliberately not altered before transport. Normalization
/// here only makes presentation ordering case-insensitive and tolerant of
/// decomposed diacritics.
List<MentionCandidate> rankMentionCandidates(
  Iterable<MentionCandidate> candidates,
  String term,
) {
  final String query = _normalize(term);
  final List<MentionCandidate> result = List<MentionCandidate>.of(candidates);
  result.sort((MentionCandidate left, MentionCandidate right) {
    final int rank = _matchRank(
      left,
      query,
    ).compareTo(_matchRank(right, query));
    if (rank != 0) return rank;
    final int username = _normalize(
      left.user.username,
    ).compareTo(_normalize(right.user.username));
    if (username != 0) return username;
    return left.user.id.compareTo(right.user.id);
  });
  return List<MentionCandidate>.unmodifiable(result);
}

int _matchRank(MentionCandidate candidate, String query) {
  if (query.isEmpty) return 3;
  final String username = _normalize(candidate.user.username);
  if (username == query) return 0;
  if (username.startsWith(query)) return 1;
  final String displayName = _normalize(candidate.user.fullName);
  return displayName.startsWith(query) ? 2 : 3;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[\u0300-\u036f]'), '');
