import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/theme/app_typography.dart';

void main() {
  testWidgets('defines content styles between Material body sizes', (
    WidgetTester tester,
  ) async {
    late TextTheme textTheme;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            textTheme = Theme.of(context).textTheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(textTheme.bodyMedium?.fontSize, 14);
    expect(textTheme.channelName.fontSize, 15);
    expect(textTheme.messageBody.fontSize, 15);
    expect(textTheme.bodyLarge?.fontSize, 16);
  });
}
