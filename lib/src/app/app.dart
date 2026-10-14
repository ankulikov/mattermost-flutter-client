import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/router.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/user_preferences.dart';

class MattermostApp extends ConsumerWidget {
  const MattermostApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemePreference preference = ref.watch(
      appThemeProvider.select((AppThemeState state) => state.preference),
    );
    return MaterialApp.router(
      title: 'Mattermost',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: MattermostTheme.light(),
      darkTheme: MattermostTheme.dark(),
      themeMode: switch (preference) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      builder: (BuildContext context, Widget? child) {
        final ThemeData theme = Theme.of(context);
        final SystemUiOverlayStyle base = theme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: base.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: theme.colorScheme.surface,
            systemNavigationBarDividerColor: theme.colorScheme.outlineVariant,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
