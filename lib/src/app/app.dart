import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/router.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_available_dialog.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_page.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

class MattermostApp extends ConsumerWidget {
  const MattermostApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemePreference preference = ref.watch(
      appThemeProvider.select((AppThemeState state) => state.preference),
    );
    return _UpdateLifecycleCoordinator(
      child: MaterialApp.router(
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
      ),
    );
  }
}

class _UpdateLifecycleCoordinator extends ConsumerStatefulWidget {
  const _UpdateLifecycleCoordinator({required this.child});

  final Widget child;

  @override
  ConsumerState<_UpdateLifecycleCoordinator> createState() =>
      _UpdateLifecycleCoordinatorState();
}

class _UpdateLifecycleCoordinatorState
    extends ConsumerState<_UpdateLifecycleCoordinator> {
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _checkScheduled = false;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleStartupCheck();
      }
    });
  }

  void _scheduleStartupCheck() {
    if (!_isAndroid || _checkScheduled) return;
    _checkScheduled = true;
    unawaited(_checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final UpdateCatalog? catalog = await ref
        .read(appUpdateControllerProvider.notifier)
        .checkIfDue();
    final UpdateCandidate? candidate = catalog?.candidate;
    final BuildContext? dialogContext = appNavigatorKey.currentContext;
    if (!mounted ||
        candidate == null ||
        dialogContext == null ||
        !dialogContext.mounted ||
        _dialogVisible) {
      return;
    }

    _dialogVisible = true;
    final AppUpdateAvailableAction? action =
        await showDialog<AppUpdateAvailableAction>(
          context: dialogContext,
          barrierDismissible: false,
          builder: (BuildContext context) => AppUpdateAvailableDialog(
            currentVersion: catalog!.installed.displayVersion,
            newVersion: candidate.release.version.displayName,
          ),
        );
    _dialogVisible = false;
    if (!mounted) return;
    if (action == AppUpdateAvailableAction.updateNow) {
      final BuildContext? navigationContext = appNavigatorKey.currentContext;
      if (navigationContext != null && navigationContext.mounted) {
        await Navigator.of(navigationContext).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const AppUpdatePage(),
          ),
        );
      }
      return;
    }
    await ref
        .read(appUpdateControllerProvider.notifier)
        .postponeAutomaticChecks();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
