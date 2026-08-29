import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/app/di/app_providers.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_strings.dart';

/// Adaptive entry point for Mattermost SAML and OpenID Connect login.
///
/// The browser surface itself is owned by [SsoBrowserGateway]. This widget only
/// displays progress and invokes the presentation controller.
class SsoLoginDialog extends ConsumerStatefulWidget {
  const SsoLoginDialog({super.key});

  @override
  ConsumerState<SsoLoginDialog> createState() => _SsoLoginDialogState();
}

class _SsoLoginDialogState extends ConsumerState<SsoLoginDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _serverController = TextEditingController();

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    ref.listen<AuthState>(authControllerProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      if (next.phase == AuthPhase.signedIn && mounted) {
        Navigator.of(context).pop();
      }
    });
    final bool browserBusy =
        auth.phase == AuthPhase.authenticatingInBrowser ||
        auth.phase == AuthPhase.validatingToken;
    final bool discoveryBusy = auth.phase == AuthPhase.discoveringServer;
    return PopScope(
      canPop: !browserBusy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop && browserBusy) {
          unawaited(ref.read(authControllerProvider.notifier).cancelSso());
        }
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: switch (auth.phase) {
              AuthPhase.choosingSso => _SsoChooser(
                auth: auth,
                onAuthenticate: (SsoProvider provider) => unawaited(
                  ref
                      .read(authControllerProvider.notifier)
                      .authenticate(provider),
                ),
                onChangeServer: ref
                    .read(authControllerProvider.notifier)
                    .changeServer,
              ),
              AuthPhase.authenticatingInBrowser ||
              AuthPhase.validatingToken => _BrowserProgress(
                validating: auth.phase == AuthPhase.validatingToken,
                onCancel: () => unawaited(
                  ref.read(authControllerProvider.notifier).cancelSso(),
                ),
              ),
              _ => _ServerForm(
                formKey: _formKey,
                controller: _serverController,
                busy: discoveryBusy,
                failure: auth.failure,
                hasServerToRetry: auth.serverUrl != null,
                onSubmit: _discover,
                onRetry: () => unawaited(
                  ref.read(authControllerProvider.notifier).retryDiscovery(),
                ),
                onCancel: _cancel,
              ),
            },
          ),
        ),
      ),
    );
  }

  void _discover() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    unawaited(
      ref
          .read(authControllerProvider.notifier)
          .discoverServer(_serverController.text),
    );
  }

  void _cancel() {
    ref.read(authControllerProvider.notifier).changeServer();
    Navigator.of(context).pop();
  }
}

class _ServerForm extends StatelessWidget {
  const _ServerForm({
    required this.formKey,
    required this.controller,
    required this.busy,
    required this.failure,
    required this.hasServerToRetry,
    required this.onSubmit,
    required this.onRetry,
    required this.onCancel,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool busy;
  final AuthFailureKind? failure;
  final bool hasServerToRetry;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final AuthFailureKind? displayedFailure = failure;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(AuthStrings.title, style: TextStyle(fontSize: 22)),
        const SizedBox(height: 12),
        const Text(AuthStrings.description),
        const SizedBox(height: 20),
        Form(
          key: formKey,
          child: TextFormField(
            key: const ValueKey<String>('sso-server-url'),
            controller: controller,
            enabled: !busy,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.url],
            decoration: const InputDecoration(
              labelText: AuthStrings.serverLabel,
              hintText: AuthStrings.serverHint,
              border: OutlineInputBorder(),
            ),
            onFieldSubmitted: (_) => onSubmit(),
            validator: (String? value) => value == null || value.trim().isEmpty
                ? AuthStrings.invalidInput
                : null,
          ),
        ),
        if (busy) ...<Widget>[
          const SizedBox(height: 16),
          const _LoadingLabel(AuthStrings.loadingMethods),
        ],
        if (displayedFailure != null) ...<Widget>[
          const SizedBox(height: 16),
          _FailureMessage(displayedFailure),
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            TextButton(
              onPressed: busy ? null : onCancel,
              child: const Text(AuthStrings.cancel),
            ),
            if (displayedFailure != null && hasServerToRetry)
              OutlinedButton(
                onPressed: busy ? null : onRetry,
                child: const Text(AuthStrings.retry),
              ),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              child: const Text(AuthStrings.continueLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _SsoChooser extends StatelessWidget {
  const _SsoChooser({
    required this.auth,
    required this.onAuthenticate,
    required this.onChangeServer,
  });

  final AuthState auth;
  final ValueChanged<SsoProvider> onAuthenticate;
  final VoidCallback onChangeServer;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Text(AuthStrings.title, style: TextStyle(fontSize: 22)),
      const SizedBox(height: 8),
      Text(auth.serverUrl?.host ?? ''),
      const SizedBox(height: 20),
      const Text(AuthStrings.chooseMethod),
      const SizedBox(height: 12),
      for (final SsoOption option in auth.ssoOptions) ...<Widget>[
        Semantics(
          button: true,
          label: option.displayLabel,
          child: FilledButton(
            onPressed: () => onAuthenticate(option.provider),
            child: Text(option.displayLabel),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (auth.failure != null) ...<Widget>[
        const SizedBox(height: 8),
        _FailureMessage(auth.failure!),
      ],
      const SizedBox(height: 12),
      TextButton(
        onPressed: onChangeServer,
        child: const Text(AuthStrings.changeServer),
      ),
    ],
  );
}

class _BrowserProgress extends StatelessWidget {
  const _BrowserProgress({required this.validating, required this.onCancel});

  final bool validating;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Text(AuthStrings.title, style: TextStyle(fontSize: 22)),
      const SizedBox(height: 24),
      _LoadingLabel(
        validating ? AuthStrings.validatingSession : AuthStrings.openingBrowser,
      ),
      const SizedBox(height: 24),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onCancel,
          child: const Text(AuthStrings.cancel),
        ),
      ),
    ],
  );
}

class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage(this.failure);

  final AuthFailureKind failure;

  @override
  Widget build(BuildContext context) => Text(
    switch (failure) {
      AuthFailureKind.invalidServer => AuthStrings.invalidInput,
      AuthFailureKind.ssoUnavailable => AuthStrings.ssoUnavailable,
      AuthFailureKind.browserUnavailable => AuthStrings.browserUnavailable,
      AuthFailureKind.cancelled => '',
      AuthFailureKind.ssoFailed => AuthStrings.ssoFailed,
      AuthFailureKind.tokenMissing => AuthStrings.tokenMissing,
      AuthFailureKind.invalidCredentials ||
      AuthFailureKind.sessionExpired => AuthStrings.invalidCredentials,
      AuthFailureKind.network => AuthStrings.networkError,
      AuthFailureKind.invalidResponse => AuthStrings.ssoFailed,
      AuthFailureKind.storage => AuthStrings.storageError,
    },
    textAlign: TextAlign.center,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}
