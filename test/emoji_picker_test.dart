import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/domain/models/emoji.dart';
import 'package:mattermost_flutter/src/ui/messages/widgets/emoji_picker.dart';

import 'support/fake_emoji_repository.dart';

void main() {
  testWidgets('shows recent emoji and selects a system reaction', (
    WidgetTester tester,
  ) async {
    final FakeEmojiRepository repository = FakeEmojiRepository()
      ..recent = <String>['thumbsup'];
    String? selected;

    await tester.pumpWidget(
      _app(
        EmojiPicker(
          repository: repository,
          accountId: 'account-a',
          onSelected: (String name) => selected = name,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('emoji-thumbsup')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('emoji-thumbsup')));
    expect(selected, 'thumbsup');
  });

  testWidgets('merges debounced custom results into local search', (
    WidgetTester tester,
  ) async {
    final FakeEmojiRepository repository = FakeEmojiRepository()
      ..searchResults = const <CustomEmojiReference>[
        CustomEmojiReference(
          name: 'party_parrot',
          id: 'custom-1',
          updatedAt: 4,
        ),
      ];
    String? selected;
    await tester.pumpWidget(
      _app(
        EmojiPicker(
          repository: repository,
          accountId: 'account-a',
          onSelected: (String name) => selected = name,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey<String>('emoji-search-field')),
      'party_parrot',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(repository.searchedTerms, <String>['party_parrot']);
    expect(
      find.byKey(const ValueKey<String>('emoji-party_parrot')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('emoji-party_parrot')));
    expect(selected, 'party_parrot');
  });

  testWidgets('category bar and grid fit compact width with large text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EmojiPicker(
          repository: FakeEmojiRepository(),
          accountId: 'account-a',
          onSelected: (_) {},
        ),
        width: 320,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('emoji-grid')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  Widget child, {
  double width = 500,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, height: 620, child: child),
    ),
  ),
);
