import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/theme/app_theme.dart';
import 'package:mattermost_flutter/src/features/preferences/domain/models/theme_preference.dart';
import 'package:mattermost_flutter/src/features/profile/presentation/profile_strings.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';

/// Lets the signed-in user choose the application color scheme.
class DisplaySettingsPage extends ConsumerWidget {
  const DisplaySettingsPage({super.key});

  static const double _contentMaxWidth = 760;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeState themeState = ref.watch(appThemeProvider);
    final bool busy = themeState.isLoading || themeState.isSaving;

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
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
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
