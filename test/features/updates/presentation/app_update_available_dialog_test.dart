import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_available_dialog.dart';

void main() {
  Future<ValueNotifier<AppUpdateAvailableAction?>> showDialogUnderTest(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    final ValueNotifier<AppUpdateAvailableAction?> result =
        ValueNotifier<AppUpdateAvailableAction?>(null);
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (BuildContext context) => FilledButton(
            onPressed: () async {
              result.value = await showDialog<AppUpdateAvailableAction>(
                context: context,
                builder: (BuildContext context) =>
                    const AppUpdateAvailableDialog(
                      currentVersion: '1.2.3',
                      newVersion: '2.3.4',
                    ),
              );
            },
            child: const Text('Show'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows versions and returns Update now', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<AppUpdateAvailableAction?> result =
        await showDialogUnderTest(tester);

    expect(find.text('New version available'), findsOneWidget);
    expect(
      find.text(
        'New version available. Current version: 1.2.3, '
        'New version: 2.3.4',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Update now'));
    await tester.pumpAndSettle();
    expect(result.value, AppUpdateAvailableAction.updateNow);
  });

  testWidgets('returns Later without overflowing at large text scale', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<AppUpdateAvailableAction?> result =
        await showDialogUnderTest(tester, textScale: 2);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(result.value, AppUpdateAvailableAction.later);
    expect(tester.takeException(), isNull);
  });
}
