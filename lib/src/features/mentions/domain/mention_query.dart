/// The editable `@` token currently surrounding a composer caret.
///
/// Offsets are UTF-16 offsets, matching Flutter's [TextEditingValue] offsets
/// without making the domain model depend on Flutter.
final class MentionQuery {
  const MentionQuery({
    required this.start,
    required this.end,
    required this.trigger,
    required this.term,
    required this.key,
  });

  /// Offset of the trigger character.
  final int start;

  /// Exclusive offset of the query text which should be replaced.
  final int end;
  final String trigger;

  /// The text after the trigger, preserved exactly for display and insertion.
  final String term;

  /// A whitespace-trimmed, case- and diacritic-insensitive lookup key.
  final String key;
}
