import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mattermost_flutter/src/app/router.dart';

class MattermostApp extends StatelessWidget {
  const MattermostApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0058cc)),
      useMaterial3: true,
    );
    return MaterialApp.router(
      title: 'Mattermost',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: theme,
      builder: (BuildContext context, Widget? child) =>
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child ?? const SizedBox.shrink(),
          ),
    );
  }
}
