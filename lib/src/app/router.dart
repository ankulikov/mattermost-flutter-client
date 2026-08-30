import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mattermost_flutter/src/features/bootstrap/presentation/bootstrap_page.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const BootstrapPage(),
    ),
  ],
);
