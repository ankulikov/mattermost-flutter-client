import 'package:mattermost_flutter/src/features/preferences/domain/repositories/app_settings_repository.dart';

/// Compatibility alias for the legacy account-scoped Drift adapter.
@Deprecated('Use AppSettingsRepository for process-wide application settings.')
typedef UserPreferencesRepository = AppSettingsRepository;
