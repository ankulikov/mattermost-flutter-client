import 'package:mattermost_flutter/src/features/search/domain/models/message_search.dart';

ActiveSearchFilter? activeMessageSearchFilter(String query, int caretOffset) {
  final int caret = caretOffset.clamp(0, query.length);
  int index = 0;
  while (index < query.length) {
    while (index < query.length && _isWhitespace(query[index])) {
      index++;
    }
    if (index >= query.length) break;
    final int tokenStart = index;
    final int tokenEnd = _tokenEnd(query, tokenStart);
    index = tokenEnd;
    final String token = query.substring(tokenStart, tokenEnd);
    final int colon = token.indexOf(':');
    if (colon <= 0) continue;
    final SearchFilterKind? kind = _filterKind(token.substring(0, colon));
    if (kind == null || caret < tokenStart || caret > tokenEnd) continue;
    return ActiveSearchFilter(
      kind: kind,
      filterStart: tokenStart,
      valueStart: tokenStart + colon + 1,
      valueEnd: tokenEnd,
    );
  }
  return null;
}

String normalizeMessageSearchTerms(String query) => query
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[‘’]'), "'")
    .trim();

bool canSubmitMessageSearch(String query) =>
    normalizeMessageSearchTerms(query).isNotEmpty;

String insertMessageSearchFilterPrefix({
  required String query,
  required int caretOffset,
  required SearchFilterKind kind,
}) {
  final int caret = caretOffset.clamp(0, query.length);
  final String before = query.substring(0, caret);
  final bool needsLeading =
      before.isNotEmpty &&
      !_isWhitespace(before[before.length - 1]) &&
      before[before.length - 1] != ':';
  return '${needsLeading ? '$before ' : before}${kind.name}:'
      '${query.substring(caret)}';
}

String insertMessageSearchSuggestion({
  required String query,
  required int caretOffset,
  required String replacement,
}) {
  final ActiveSearchFilter? active = activeMessageSearchFilter(
    query,
    caretOffset,
  );
  if (active == null) return _insertAtCaret(query, caretOffset, replacement);
  return _withTokenSpacing(
    query.substring(0, active.valueStart),
    replacement,
    query.substring(active.valueEnd),
  );
}

String formatMessageSearchDate(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${pad(date.month)}-${pad(date.day)}';
}

String _insertAtCaret(String query, int caretOffset, String insertion) {
  final int caret = caretOffset.clamp(0, query.length);
  return _withTokenSpacing(
    query.substring(0, caret),
    insertion,
    query.substring(caret),
  );
}

String _withTokenSpacing(String before, String insertion, String after) {
  final bool needsLeading =
      before.isNotEmpty &&
      !_isWhitespace(before[before.length - 1]) &&
      before[before.length - 1] != ':';
  final bool needsTrailing = after.isEmpty || !_isWhitespace(after[0]);
  return '${needsLeading ? '$before ' : before}$insertion'
      '${needsTrailing ? ' ' : ''}$after';
}

SearchFilterKind? _filterKind(String value) => switch (value.toLowerCase()) {
  'from' => SearchFilterKind.from,
  'in' => SearchFilterKind.inChannel,
  'before' => SearchFilterKind.before,
  'after' => SearchFilterKind.after,
  _ => null,
};

bool _isWhitespace(String character) => RegExp(r'\s').hasMatch(character);

int _tokenEnd(String query, int start) {
  int index = start;
  String? closingQuote;
  while (index < query.length) {
    final String character = query[index];
    if (closingQuote != null) {
      if (character == closingQuote) closingQuote = null;
      index++;
      continue;
    }
    if (_isWhitespace(character)) return index;
    closingQuote = switch (character) {
      '"' => '"',
      "'" => "'",
      '“' => '”',
      '‘' => '’',
      _ => null,
    };
    index++;
  }
  return index;
}
