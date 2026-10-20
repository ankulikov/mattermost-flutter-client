import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/core/async/operation_status.dart';
import 'package:mattermost_flutter/src/features/updates/domain/models/app_update.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_controller.dart';
import 'package:mattermost_flutter/src/features/updates/presentation/app_update_strings.dart';
import 'package:mattermost_flutter/src/ui/core/layout/app_breakpoints.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _pullRequestReference = RegExp(
  r'(?:\[[^\]]*\]\()?(https://github\.com/ankulikov/mattermost-flutter-client/pull/(\d+))(?:\))?',
);
final RegExp _compareReference = RegExp(
  r'(?:\[[^\]]*\]\()?(https://github\.com/ankulikov/mattermost-flutter-client/compare/([^/?#\s)]+\.\.\.[^/?#\s)]+))(?:\))?',
);

class AppUpdatePage extends ConsumerStatefulWidget {
  const AppUpdatePage({super.key});

  @override
  ConsumerState<AppUpdatePage> createState() => _AppUpdatePageState();
}

class _AppUpdatePageState extends ConsumerState<AppUpdatePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(appUpdateControllerProvider.notifier)
              .check(replaceCurrent: true),
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(appUpdateControllerProvider.notifier).handleResumed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUpdateViewState state = ref.watch(appUpdateControllerProvider);
    return Scaffold(
      key: const ValueKey<String>('app-update-page'),
      appBar: AppBar(title: const Text(AppUpdateStrings.title)),
      body: Stack(
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool expanded =
                  constraints.maxWidth >= AppBreakpoints.compact;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: _UpdateContent(state: state, expanded: expanded),
                ),
              );
            },
          ),
          if (state.checkStatus is OperationInProgress && state.catalog != null)
            const PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: LinearProgressIndicator(
                key: ValueKey<String>('app-update-refresh-progress'),
                semanticsLabel: AppUpdateStrings.checking,
              ),
            ),
        ],
      ),
    );
  }
}

class _UpdateContent extends ConsumerWidget {
  const _UpdateContent({required this.state, required this.expanded});

  final AppUpdateViewState state;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UpdateCatalog? catalog = state.catalog;
    if (state.supported == false) {
      return const _CenteredMessage(
        icon: Icons.system_update_alt,
        message: AppUpdateStrings.unsupported,
      );
    }
    if (catalog == null) {
      if (state.checkStatus is! OperationFailed) {
        return Center(
          child: Semantics(
            label: AppUpdateStrings.checking,
            child: const CircularProgressIndicator(),
          ),
        );
      }
      return _InitialFailure(
        error: (state.checkStatus as OperationFailed).error,
      );
    }

    final List<Widget> children = <Widget>[
      _VersionSummary(catalog: catalog, expanded: expanded),
      if (!catalog.isComplete) ...<Widget>[
        const SizedBox(height: 16),
        const _StatusCard(
          key: ValueKey<String>('app-update-partial-history'),
          icon: Icons.warning_amber_rounded,
          message: AppUpdateStrings.partialHistory,
        ),
      ],
      if (state.checkStatus case OperationFailed(
        :final Object error,
      )) ...<Widget>[
        const SizedBox(height: 16),
        _StatusCard(
          icon: Icons.cloud_off_outlined,
          message: _checkErrorMessage(error),
        ),
      ],
      const SizedBox(height: 20),
      _InstallStatus(phase: state.installPhase),
      if (state.installPhase is! UpdateInstallIdle) const SizedBox(height: 16),
      _Actions(state: state),
      if (catalog.newerReleases.isNotEmpty) ...<Widget>[
        const SizedBox(height: 32),
        Text(
          AppUpdateStrings.whatsNew,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...catalog.newerReleases.map(
          (UpdateRelease release) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ReleaseNotes(release: release),
          ),
        ),
      ],
    ];

    return ListView(
      key: ValueKey<String>(
        expanded ? 'app-update-expanded' : 'app-update-compact',
      ),
      padding: EdgeInsets.fromLTRB(
        expanded ? 32 : 20,
        24,
        expanded ? 32 : 20,
        40,
      ),
      children: children,
    );
  }
}

class _VersionSummary extends StatelessWidget {
  const _VersionSummary({required this.catalog, required this.expanded});

  final UpdateCatalog catalog;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final UpdateCandidate? candidate = catalog.candidate;
    final Widget installed = _VersionValue(
      label: AppUpdateStrings.installedVersion,
      value: catalog.installed.displayVersion,
    );
    final Widget available = _VersionValue(
      label: AppUpdateStrings.availableVersion,
      value: candidate?.release.version.displayName ?? '—',
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (expanded)
              Row(
                children: <Widget>[
                  Expanded(child: installed),
                  const SizedBox(width: 24),
                  Expanded(child: available),
                ],
              )
            else ...<Widget>[installed, const SizedBox(height: 16), available],
            const SizedBox(height: 16),
            Text(
              catalog.hasUpdates
                  ? candidate == null
                        ? AppUpdateStrings.noCompatibleBuild
                        : AppUpdateStrings.version(
                            candidate.release.version.displayName,
                          )
                  : AppUpdateStrings.upToDate,
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionValue extends StatelessWidget {
  const _VersionValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.state});

  final AppUpdateViewState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UpdateCandidate? candidate = state.catalog?.candidate;
    final bool installBusy =
        state.installPhase is UpdateInstallDownloading ||
        state.installPhase is UpdateInstallWaitingForSystem;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: <Widget>[
        OutlinedButton.icon(
          key: const ValueKey<String>('app-update-check'),
          onPressed: state.checkStatus is OperationInProgress || installBusy
              ? null
              : () => unawaited(
                  ref
                      .read(appUpdateControllerProvider.notifier)
                      .check(replaceCurrent: true),
                ),
          icon: const Icon(Icons.refresh),
          label: const Text(AppUpdateStrings.checkForUpdates),
        ),
        if (candidate != null)
          FilledButton.icon(
            key: const ValueKey<String>('app-update-install'),
            onPressed: !state.catalog!.isComplete || installBusy
                ? null
                : () => unawaited(
                    ref.read(appUpdateControllerProvider.notifier).install(),
                  ),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: Text(
              AppUpdateStrings.installVersion(
                candidate.release.version.displayName,
              ),
            ),
          ),
      ],
    );
  }
}

class _InstallStatus extends ConsumerWidget {
  const _InstallStatus({required this.phase});

  final UpdateInstallPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (phase) {
    UpdateInstallIdle() => const SizedBox.shrink(),
    UpdateInstallPermissionRequired() => _StatusCard(
      key: const ValueKey<String>('app-update-permission'),
      icon: Icons.security_outlined,
      title: AppUpdateStrings.installPermissionTitle,
      message: AppUpdateStrings.installPermissionDescription,
      action: FilledButton(
        onPressed: () => unawaited(
          ref
              .read(appUpdateControllerProvider.notifier)
              .openInstallPermissionSettings(),
        ),
        child: const Text(AppUpdateStrings.openSettings),
      ),
    ),
    UpdateInstallDownloading(:final double progress) => _DownloadProgress(
      progress: progress,
    ),
    UpdateInstallWaitingForSystem(:final bool needsConfirmation) => _StatusCard(
      icon: Icons.install_mobile_outlined,
      message: needsConfirmation
          ? AppUpdateStrings.confirmationRequired
          : AppUpdateStrings.installing,
    ),
    UpdateInstallComplete() => const _StatusCard(
      icon: Icons.check_circle_outline,
      message: AppUpdateStrings.installComplete,
    ),
    UpdateInstallFailure(:final Object error) => _StatusCard(
      icon: Icons.error_outline,
      message: _installErrorMessage(error),
      details: _rawInstallError(error),
    ),
  };
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final int percent = (progress * 100).round();
    return Semantics(
      label: AppUpdateStrings.downloadPercent(percent),
      child: Card.outlined(
        key: const ValueKey<String>('app-update-download-progress'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                progress >= 1
                    ? AppUpdateStrings.verifying
                    : AppUpdateStrings.downloading,
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Text('$percent%', textAlign: TextAlign.end),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.release});

  final UpdateRelease release;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            release.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            AppUpdateStrings.version(release.version.displayName),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          release.notes.isEmpty
              ? const Text(AppUpdateStrings.noReleaseNotes)
              : _ReleaseNotesMarkdown(data: release.notes),
        ],
      ),
    ),
  );
}

/// Displays GitHub release notes as selectable Markdown.
///
/// Release metadata is remote content. HTTP(S) links open in the external
/// browser, and images are represented by their alternative text instead of
/// loading remote resources.
class _ReleaseNotesMarkdown extends StatelessWidget {
  const _ReleaseNotesMarkdown({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle bodyStyle = theme.textTheme.bodyMedium!;
    final ColorScheme colors = theme.colorScheme;
    return MarkdownBody(
      data: normalizeReleaseNotesMarkdown(data),
      selectable: true,
      softLineBreak: true,
      onTapLink: (_, String? href, _) {
        final Uri? uri = href == null ? null : Uri.tryParse(href);
        if (uri == null ||
            !const <String>{'http', 'https'}.contains(uri.scheme)) {
          return;
        }
        unawaited(_openReleaseNotesLink(uri));
      },
      imageBuilder: (_, _, String? alt) => Text(alt ?? ''),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: bodyStyle,
        blockSpacing: 8,
        a: bodyStyle.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
          decorationColor: colors.primary,
        ),
        code: bodyStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: colors.surfaceContainerHighest,
        ),
        h1: theme.textTheme.headlineSmall,
        h2: theme.textTheme.titleLarge,
        h3: theme.textTheme.titleMedium,
        h4: theme.textTheme.titleSmall,
        h5: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        h6: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
      ),
    );
  }
}

/// Converts known GitHub release references to concise Markdown links.
///
/// Both generated plain URLs and links GitHub has already labeled are accepted.
String normalizeReleaseNotesMarkdown(String markdown) => markdown
    .replaceAllMapped(_pullRequestReference, (Match match) {
      final String url = match.group(1)!;
      final String number = match.group(2)!;
      return '[#$number]($url)';
    })
    .replaceAllMapped(_compareReference, (Match match) {
      final String url = match.group(1)!;
      final String versions = match.group(2)!;
      return '[$versions]($url)';
    });

Future<void> _openReleaseNotesLink(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // The platform owns the external browser; failure leaves the dialog open.
  }
}

class _InitialFailure extends ConsumerWidget {
  const _InitialFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 16),
          Text(_checkErrorMessage(error), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(
              ref
                  .read(appUpdateControllerProvider.notifier)
                  .check(replaceCurrent: true),
            ),
            child: const Text(AppUpdateStrings.retry),
          ),
        ],
      ),
    ),
  );
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.message,
    this.title,
    this.details,
    this.action,
    super.key,
  });

  final IconData icon;
  final String? title;
  final String message;
  final String? details;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(title!, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                ],
                Text(message),
                if (details case final String details
                    when details.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  SelectionArea(
                    child: Text(
                      details,
                      key: const ValueKey<String>('app-update-error-details'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
                if (action != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: action,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _checkErrorMessage(Object error) =>
    error is AppUpdateRateLimitedException
    ? AppUpdateStrings.rateLimited
    : AppUpdateStrings.checkFailed;

String _installErrorMessage(Object error) =>
    error is AppUpdateDownloadException && error.reason == 'checksum_mismatch'
    ? AppUpdateStrings.checksumFailed
    : AppUpdateStrings.installFailed;

String _rawInstallError(Object error) => switch (error) {
  AppUpdateDownloadException(:final String reason) => reason,
  AppUpdateInstallException(:final String reason, :final String? rawError) =>
    rawError ?? reason,
  UpdateInstallerFailed(:final String reason, :final String? rawError) =>
    rawError == null ? reason : '$reason\n$rawError',
  UpdateInstallerCancelled() => 'installation_cancelled',
  _ => error.toString(),
};
