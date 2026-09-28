import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_completeness.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';

void main() {
  test(
    'maps Inbox completeness, source retries, and count labels centrally',
    () {
      for (final InboxCompleteness completeness in InboxCompleteness.values) {
        expect(InboxStrings.completeness(completeness), isNotEmpty);
      }
      for (final InboxSourceScope scope in InboxSourceScope.values) {
        expect(InboxStrings.sourceFailure(scope), isNotEmpty);
        expect(InboxStrings.retrySource(scope), isNotEmpty);
      }

      expect(InboxStrings.messages(1), '1 message');
      expect(InboxStrings.messages(2), '2 messages');
      expect(
        InboxStrings.itemSemantics('Ada Lovelace', 'Please review this'),
        'Ada Lovelace. Please review this',
      );
    },
  );
}
