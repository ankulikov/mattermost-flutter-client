import 'package:flutter/material.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_strings.dart';

enum AppUpdateAvailableAction { updateNow, later }

class AppUpdateAvailableDialog extends StatelessWidget {
  const AppUpdateAvailableDialog({
    required this.currentVersion,
    required this.newVersion,
    super.key,
  });

  final String currentVersion;
  final String newVersion;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(AppUpdateStrings.updateAvailableTitle),
    content: Text(
      AppUpdateStrings.updateAvailable(
        currentVersion: currentVersion,
        newVersion: newVersion,
      ),
    ),
    actions: <Widget>[
      TextButton(
        key: const ValueKey<String>('app-update-later'),
        onPressed: () =>
            Navigator.of(context).pop(AppUpdateAvailableAction.later),
        child: const Text(AppUpdateStrings.later),
      ),
      FilledButton(
        key: const ValueKey<String>('app-update-now'),
        onPressed: () =>
            Navigator.of(context).pop(AppUpdateAvailableAction.updateNow),
        child: const Text(AppUpdateStrings.updateNow),
      ),
    ],
  );
}
