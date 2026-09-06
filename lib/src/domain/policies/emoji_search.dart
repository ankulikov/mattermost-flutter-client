import 'package:mattermost_flutter/src/domain/models/emoji.dart';

/// Normalizes picker input such as `:party parrot:` to a Mattermost name.
String normalizeEmojiSearchTerm(String value) {
  String normalized = value.trim().toLowerCase();
  if (normalized.startsWith(':')) normalized = normalized.substring(1);
  if (normalized.endsWith(':')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.trim().replaceAll(RegExp(r'[\s-]+'), '_');
}

/// Searches the built-in catalog without a network request.
List<SystemEmojiDefinition> searchSystemEmojis(
  List<SystemEmojiDefinition> catalog,
  String term, {
  int limit = 200,
}) {
  final String query = normalizeEmojiSearchTerm(term);
  if (query.isEmpty || limit <= 0) return const <SystemEmojiDefinition>[];
  final List<({SystemEmojiDefinition emoji, int rank, int aliasLength})>
  matches = <({SystemEmojiDefinition emoji, int rank, int aliasLength})>[];
  for (final SystemEmojiDefinition emoji in catalog) {
    int? bestRank;
    int bestLength = emoji.name.length;
    for (final String alias in emoji.aliases) {
      final int? rank = emojiSearchMatchRank(alias, query);
      if (rank != null && (bestRank == null || rank < bestRank)) {
        bestRank = rank;
        bestLength = alias.length;
      }
    }
    if (bestRank != null) {
      matches.add((emoji: emoji, rank: bestRank, aliasLength: bestLength));
    }
  }
  matches.sort((a, b) {
    final int byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    final int byLength = a.aliasLength.compareTo(b.aliasLength);
    if (byLength != 0) return byLength;
    return a.emoji.name.compareTo(b.emoji.name);
  });
  return matches
      .take(limit)
      .map((match) => match.emoji)
      .toList(growable: false);
}

/// Smaller values sort ahead of weaker matches; `null` means no match.
int? emojiSearchMatchRank(String candidate, String normalizedTerm) {
  final String value = candidate.toLowerCase().replaceAll('-', '_');
  if (value == normalizedTerm) return 0;
  if (value.startsWith(normalizedTerm)) return 1;
  if (value.split('_').any((String part) => part.startsWith(normalizedTerm))) {
    return 2;
  }
  if (value.contains(normalizedTerm)) return 3;
  if (normalizedTerm.length >= 4 && _isSubsequence(normalizedTerm, value)) {
    return 4;
  }
  return null;
}

bool _isSubsequence(String query, String candidate) {
  var queryIndex = 0;
  for (var index = 0; index < candidate.length; index += 1) {
    if (candidate.codeUnitAt(index) == query.codeUnitAt(queryIndex)) {
      queryIndex += 1;
      if (queryIndex == query.length) return true;
    }
  }
  return false;
}
