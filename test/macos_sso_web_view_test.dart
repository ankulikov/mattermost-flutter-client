import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/app/macos_sso_web_view.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';

void main() {
  testWidgets('cancelling the sign-in closes the embedded browser', (
    WidgetTester tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey));
    final closeRequested = Completer<void>();
    var dismissed = false;
    var disposed = false;

    final Future<void> closed = presentMacosSsoWebView(
      navigatorKey.currentState!,
      const Text('Identity provider'),
      closeRequested.future,
      () => dismissed = true,
    );
    unawaited(closed.then((_) => disposed = true));
    await tester.pumpAndSettle();
    expect(find.text('Identity provider'), findsOneWidget);

    await tester.tap(find.text(AuthStrings.cancel));
    await tester.pump();
    expect(dismissed, isTrue);
    expect(disposed, isFalse);
    await tester.pumpAndSettle();
    await closed;

    expect(find.text('Identity provider'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('closing SSO removes only the browser route', (
    WidgetTester tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey));
    final NavigatorState navigator = navigatorKey.currentState!;
    final closeRequested = Completer<void>();
    final Future<void> closed = presentMacosSsoWebView(
      navigator,
      const Text('Identity provider'),
      closeRequested.future,
      () {},
    );
    await tester.pumpAndSettle();
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another route')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    closeRequested.complete();
    await tester.pumpAndSettle();
    await closed;

    expect(find.text('Another route'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Identity provider'), findsNothing);
  });

  testWidgets('disposing the navigator completes the browser presentation', (
    WidgetTester tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey));
    final closeRequested = Completer<void>();
    var closed = false;
    unawaited(
      presentMacosSsoWebView(
        navigatorKey.currentState!,
        const Text('Identity provider'),
        closeRequested.future,
        () {},
      ).then((_) => closed = true),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}

Widget _app(GlobalKey<NavigatorState> navigatorKey) => MaterialApp(
  navigatorKey: navigatorKey,
  home: const Scaffold(body: Text('Home')),
);
