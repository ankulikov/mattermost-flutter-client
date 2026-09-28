import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/features/inbox/domain/models/inbox_settings.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_settings_controller.dart';
import 'package:mattermost_flutter/src/features/inbox/presentation/inbox_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

/// Server-backed configuration for the client-owned Inbox projection.
///
/// This screen deliberately has no controls for Mattermost desktop settings.
/// Those settings remain the authoritative upper bound for what can appear in
/// Inbox and are displayed as read-only context only.
class InboxSettingsPage extends ConsumerWidget {
  const InboxSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<InboxSettingsViewState> value = ref.watch(
      inboxSettingsProvider,
    );
    return Scaffold(
      appBar: AppBar(title: const Text(InboxStrings.settingsTitle)),
      body: value.when(
        loading: () => Semantics(
          label: InboxStrings.settingsLoading,
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (Object error, StackTrace stackTrace) => _InitialFailure(
          onRetry: ref.read(inboxSettingsProvider.notifier).retry,
        ),
        data: (InboxSettingsViewState state) => _InboxSettingsForm(
          state: state,
          controller: ref.read(inboxSettingsProvider.notifier),
        ),
      ),
    );
  }
}

class _InitialFailure extends StatelessWidget {
  const _InitialFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(InboxStrings.settingsLoadFailed),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: InboxStrings.retryInboxSettings,
            onTap: onRetry,
            child: ExcludeSemantics(
              child: OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                child: const Text(InboxStrings.retry),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InboxSettingsForm extends StatelessWidget {
  const _InboxSettingsForm({required this.state, required this.controller});

  final InboxSettingsViewState state;
  final InboxSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final bool saving = state.saveStatus is OperationInProgress;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool expanded = constraints.maxWidth >= 720;
        final Widget sources = _SourcesSection(
          settings: state.settings,
          enabled: !saving,
          controller: controller,
        );
        final Widget behavior = _BehaviorSection(
          settings: state.settings,
          enabled: !saving,
          controller: controller,
        );
        return FocusTraversalGroup(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _DesktopPolicyContext(),
                  const SizedBox(height: 16),
                  _SwitchRow(
                    title: InboxStrings.settingsEnabled,
                    subtitle: InboxStrings.settingsEnabledDescription,
                    value: state.settings.enabled,
                    enabled: !saving,
                    onChanged: controller.setEnabled,
                  ),
                  const SizedBox(height: 16),
                  if (expanded)
                    KeyedSubtree(
                      key: const ValueKey<String>(
                        'inbox-settings-expanded-layout',
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: sources),
                          const SizedBox(width: 16),
                          Expanded(child: behavior),
                        ],
                      ),
                    )
                  else ...<Widget>[
                    KeyedSubtree(
                      key: const ValueKey<String>(
                        'inbox-settings-compact-layout',
                      ),
                      child: Column(
                        children: <Widget>[
                          sources,
                          const SizedBox(height: 16),
                          behavior,
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (state.saveStatus is OperationFailed)
                    MaterialBanner(
                      content: const Text(InboxStrings.settingsSaveFailed),
                      actions: <Widget>[
                        Semantics(
                          button: true,
                          label: InboxStrings.retrySaveInboxSettings,
                          onTap: () => unawaited(controller.save()),
                          child: ExcludeSemantics(
                            child: TextButton(
                              onPressed: () => unawaited(controller.save()),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              child: const Text(InboxStrings.retry),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (state.saveStatus is OperationFailed)
                    const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      key: const ValueKey<String>('inbox-settings-save'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: saving
                          ? null
                          : () => unawaited(controller.save()),
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        saving
                            ? InboxStrings.settingsSaving
                            : InboxStrings.settingsSave,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopPolicyContext extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: InboxStrings.desktopPolicySemantics,
    readOnly: true,
    child: ExcludeSemantics(
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text(InboxStrings.desktopPolicyTitle),
          subtitle: const Text(InboxStrings.desktopPolicyDescription),
        ),
      ),
    ),
  );
}

class _SourcesSection extends StatelessWidget {
  const _SourcesSection({
    required this.settings,
    required this.enabled,
    required this.controller,
  });

  final InboxSettings settings;
  final bool enabled;
  final InboxSettingsController controller;

  @override
  Widget build(BuildContext context) => _SettingsSection(
    title: InboxStrings.settingsSourcesTitle,
    children: <Widget>[
      _SwitchRow(
        title: InboxStrings.settingsDirectMessages,
        value: settings.sources.directMessages,
        enabled: enabled,
        onChanged: controller.setDirectMessages,
      ),
      _SwitchRow(
        title: InboxStrings.settingsGroupMessages,
        value: settings.sources.groupMessages,
        enabled: enabled,
        onChanged: controller.setGroupMessages,
      ),
      _SwitchRow(
        title: InboxStrings.settingsMentions,
        value: settings.sources.mentions,
        enabled: enabled,
        onChanged: controller.setMentions,
      ),
      _SwitchRow(
        title: InboxStrings.settingsFollowedThreads,
        value: settings.sources.followedThreads,
        enabled: enabled,
        onChanged: controller.setFollowedThreads,
      ),
      _SwitchRow(
        title: InboxStrings.settingsAllActivity,
        subtitle: InboxStrings.settingsAllActivityDescription,
        value: settings.sources.allActivity,
        enabled: enabled,
        onChanged: controller.setAllActivity,
      ),
      const SizedBox(height: 8),
      _EnumField<InboxAutomationVisibility>(
        label: InboxStrings.settingsAutomations,
        value: settings.sources.automations,
        enabled: enabled,
        values: InboxAutomationVisibility.values,
        labelFor: _automationLabel,
        onChanged: controller.setAutomations,
      ),
    ],
  );

  String _automationLabel(InboxAutomationVisibility value) => switch (value) {
    InboxAutomationVisibility.include => InboxStrings.settingsAutomationInclude,
    InboxAutomationVisibility.exclude => InboxStrings.settingsAutomationExclude,
    InboxAutomationVisibility.separate =>
      InboxStrings.settingsAutomationSeparate,
  };
}

class _BehaviorSection extends StatelessWidget {
  const _BehaviorSection({
    required this.settings,
    required this.enabled,
    required this.controller,
  });

  final InboxSettings settings;
  final bool enabled;
  final InboxSettingsController controller;

  @override
  Widget build(BuildContext context) => _SettingsSection(
    title: InboxStrings.settingsBehaviorTitle,
    children: <Widget>[
      _SwitchRow(
        title: InboxStrings.settingsReactivateOnMention,
        subtitle: InboxStrings.settingsReactivateOnMentionDescription,
        value: settings.postponed.reactivateOnMention,
        enabled: enabled,
        onChanged: controller.setReactivateOnMention,
      ),
      _SwitchRow(
        title: InboxStrings.settingsRemoveOnOpen,
        subtitle: InboxStrings.settingsRemoveOnOpenDescription,
        value: settings.postponed.removeOnOpen,
        enabled: enabled,
        onChanged: controller.setRemoveOnOpen,
      ),
      const SizedBox(height: 8),
      _SwitchRow(
        title: InboxStrings.settingsShowMessagePreview,
        subtitle: InboxStrings.settingsShowMessagePreviewDescription,
        value: settings.inAppNotification.showMessagePreview,
        enabled: enabled,
        onChanged: controller.setShowMessagePreview,
      ),
      const SizedBox(height: 8),
      _EnumField<InboxDirectGroupingMode>(
        label: InboxStrings.settingsDirectGrouping,
        value: settings.directGrouping.mode,
        enabled: enabled,
        values: InboxDirectGroupingMode.values,
        labelFor: _groupingLabel,
        onChanged: controller.setDirectGroupingMode,
      ),
    ],
  );

  String _groupingLabel(InboxDirectGroupingMode value) => switch (value) {
    InboxDirectGroupingMode.none => InboxStrings.settingsGroupingNone,
    InboxDirectGroupingMode.consecutive =>
      InboxStrings.settingsGroupingConsecutive,
    InboxDirectGroupingMode.conversation =>
      InboxStrings.settingsGroupingConversation,
  };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: title,
    hint: subtitle,
    toggled: value,
    enabled: enabled,
    onTap: enabled ? () => onChanged(!value) : null,
    child: ExcludeSemantics(
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    ),
  );
}

class _EnumField<T> extends StatelessWidget {
  const _EnumField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final T value;
  final bool enabled;
  final List<T> values;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: values
        .map(
          (T option) =>
              DropdownMenuItem<T>(value: option, child: Text(labelFor(option))),
        )
        .toList(growable: false),
    onChanged: enabled
        ? (T? option) {
            if (option != null) onChanged(option);
          }
        : null,
  );
}
