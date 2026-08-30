import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/app/router.dart';

class MattermostApp extends StatelessWidget {
  const MattermostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Mattermost',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0058cc)),
        useMaterial3: true,
      ),
    );
  }
}
