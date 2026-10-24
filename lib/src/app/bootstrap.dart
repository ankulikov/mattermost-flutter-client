import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/app.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/data/providers/repository_providers.dart';
import 'package:mattermost_flutter/src/features/preferences/data/repositories/shared_preferences_app_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';

Future<void> bootstrapMattermostApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferencesAppPreferencesRepository repository =
      SharedPreferencesAppPreferencesRepository();
  ThemePreference initialTheme = ThemePreference.light;
  try {
    initialTheme = await repository.readTheme();
  } on Object {
    // A storage failure must not prevent the application from starting.
  }
  runApp(
    ProviderScope(
      overrides: [
        appSettingsRepositoryProvider.overrideWithValue(repository),
        initialAppThemeProvider.overrideWithValue(initialTheme),
      ],
      child: const MattermostApp(),
    ),
  );
}
