import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';

Future<void> presentMacosSsoWebView(
  NavigatorState navigator,
  Widget webView,
  Future<void> closeRequested,
  VoidCallback onDismissed,
) async {
  final route = MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (BuildContext context) => Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(AuthStrings.signIn),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AuthStrings.cancel),
          ),
        ],
      ),
      body: SafeArea(child: webView),
    ),
  );
  unawaited(
    closeRequested.then((_) {
      if (navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    }),
  );
  unawaited(navigator.push(route).then<void>((_) => onDismissed()));
  await route.completed;
}
