import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/find_mention_query.dart';
import 'package:mattermost_flutter/src/features/mentions/domain/mention_query.dart';

void main() {
  MentionQuery? query(String text, {int? caret}) => findMentionQuery(
    text: text,
    selectionStart: caret ?? text.length,
    selectionEnd: caret ?? text.length,
  );

  group('findMentionQuery', () {
    test(
      'finds ASCII and fullwidth mention triggers at supported boundaries',
      () {
        expect(query('@ann')?.start, 0);
        expect(query('Hi (@Анна')?.term, 'Анна');
        expect(query('Hi ＠José')?.trigger, '＠');
        expect(query('Hi ＠José')?.key, 'jose');
      },
    );

    test(
      'preserves a Unicode multi-word term while normalizing lookup key',
      () {
        final MentionQuery? result = query('@Jo\u0301se Silva-2');
        expect(result?.term, 'Jóse Silva-2');
        expect(result?.key, 'jose silva-2');
        expect(result?.end, '@Jóse Silva-2'.length);
      },
    );

    test('rejects selections, email-like text, atoms and malformed terms', () {
      expect(
        findMentionQuery(text: '@ann', selectionStart: 1, selectionEnd: 4),
        isNull,
      );
      expect(query('person@ann'), isNull);
      expect(query('\uFFFC@ann'), isNull);
      expect(query('@@ann'), isNull);
      expect(query('@one  two'), isNull);
      expect(query('@ann!'), isNull);
      expect(query('@ann\n'), isNull);
    });

    test('returns the token that surrounds the caret', () {
      expect(query('text @ann later', caret: 9)?.term, 'ann');
      expect(query('text @ann, later', caret: 10), isNull);
    });
  });
}
