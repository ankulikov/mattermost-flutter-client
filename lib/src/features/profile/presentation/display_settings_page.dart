import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/repositories/sidebar_view_preferences_repository.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_strings.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_spacing.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

/// Lets the signed-in user choose the application color scheme.
class DisplaySettingsPage extends ConsumerStatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  ConsumerState<DisplaySettingsPage> createState() =>
      _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends ConsumerState<DisplaySettingsPage> {
  bool _savingSidebarSetting = false;

  @override
  Widget build(BuildContext context) {
    final AppThemeState themeState = ref.watch(appThemeProvider);
    final bool busy = themeState.isLoading || themeState.isSaving;
    final AuthSession? session = ref.watch(authSessionProvider);
    final AsyncValue<SidebarViewPreferences>? sidebarPreferences =
        session == null
        ? null
        : ref.watch(sidebarViewPreferencesProvider(session.durableDataScopeId));

    return Scaffold(
      key: const ValueKey<String>('display-settings-page'),
      appBar: AppBar(title: const Text(ProfileStrings.display)),
      body: Stack(
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool expanded =
                  constraints.maxWidth >= AppBreakpoints.compact;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppLayout.readableContentWidth,
                  ),
                  child: ListView(
                    key: const ValueKey<String>('display-settings-scroll-view'),
                    padding: EdgeInsets.fromLTRB(
                      expanded ? 32 : 20,
                      24,
                      expanded ? 32 : 20,
                      32,
                    ),
                    children: <Widget>[
                      Text(
                        ProfileStrings.theme,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ProfileStrings.themeDescription,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      RadioGroup<ThemePreference>(
                        groupValue: themeState.preference,
                        onChanged: (ThemePreference? preference) {
                          if (busy ||
                              preference == null ||
                              preference == themeState.preference) {
                            return;
                          }
                          unawaited(_updateTheme(context, ref, preference));
                        },
                        child: Card.outlined(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: expanded
                              ? Row(
                                  key: ValueKey<String>(
                                    'display-settings-expanded',
                                  ),
                                  children: <Widget>[
                                    Expanded(
                                      child: _ThemeChoice(
                                        preference: ThemePreference.light,
                                        icon: Icons.light_mode_outlined,
                                        label: ProfileStrings.lightTheme,
                                        enabled: !busy,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: 72,
                                      child: VerticalDivider(width: 1),
                                    ),
                                    Expanded(
                                      child: _ThemeChoice(
                                        preference: ThemePreference.dark,
                                        icon: Icons.dark_mode_outlined,
                                        label: ProfileStrings.darkTheme,
                                        enabled: !busy,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  key: ValueKey<String>(
                                    'display-settings-compact',
                                  ),
                                  children: <Widget>[
                                    _ThemeChoice(
                                      preference: ThemePreference.light,
                                      icon: Icons.light_mode_outlined,
                                      label: ProfileStrings.lightTheme,
                                      enabled: !busy,
                                    ),
                                    const Divider(height: 1),
                                    _ThemeChoice(
                                      preference: ThemePreference.dark,
                                      icon: Icons.dark_mode_outlined,
                                      label: ProfileStrings.darkTheme,
                                      enabled: !busy,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      if (sidebarPreferences?.value
                          case final SidebarViewPreferences
                              preferences) ...<Widget>[
                        const SizedBox(height: 32),
                        Text(
                          ProfileStrings.channelList,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 20),
                        Card.outlined(
                          margin: EdgeInsets.zero,
                          child: SwitchListTile(
                            key: const ValueKey<String>(
                              'show-unread-in-collapsed-folders',
                            ),
                            title: const Text(
                              ProfileStrings.showUnreadInCollapsedFolders,
                            ),
                            subtitle: const Text(
                              ProfileStrings
                                  .showUnreadInCollapsedFoldersDescription,
                            ),
                            value: preferences.showUnreadInCollapsedFolders,
                            onChanged: _savingSidebarSetting
                                ? null
                                : (bool value) => unawaited(
                                    _updateSidebarSetting(
                                      session!.durableDataScopeId,
                                      value,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          if (busy)
            const PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: LinearProgressIndicator(
                key: ValueKey<String>('display-settings-progress'),
                semanticsLabel: ProfileStrings.updatingTheme,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _updateTheme(
    BuildContext context,
    WidgetRef ref,
    ThemePreference preference,
  ) async {
    try {
      await ref.read(appThemeProvider.notifier).updateTheme(preference);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(ProfileStrings.themeUpdateFailed)),
        );
    }
  }

  Future<void> _updateSidebarSetting(
    String accountScopeId,
    bool showUnread,
  ) async {
    setState(() => _savingSidebarSetting = true);
    try {
      final SidebarViewPreferencesRepository repository = ref.read(
        sidebarViewPreferencesRepositoryProvider,
      );
      final SidebarViewPreferences current = await repository.read(
        accountScopeId,
      );
      await repository.write(
        accountScopeId,
        SidebarViewPreferences(
          hideReadChannels: current.hideReadChannels,
          hideFolderHeadings: current.hideFolderHeadings,
          showUnreadInCollapsedFolders: showUnread,
        ),
      );
      if (mounted) {
        ref.invalidate(sidebarViewPreferencesProvider(accountScopeId));
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(ProfileStrings.sidebarSettingUpdateFailed),
          ),
        );
    } finally {
      if (mounted) setState(() => _savingSidebarSetting = false);
    }
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.preference,
    required this.icon,
    required this.label,
    required this.enabled,
  });

  final ThemePreference preference;
  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => RadioListTile<ThemePreference>(
    key: ValueKey<String>('theme-${preference.name}'),
    value: preference,
    enabled: enabled,
    secondary: Icon(icon),
    title: Text(label),
  );
}
