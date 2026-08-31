import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_controller.dart';
import 'package:mattermost_flutter/src/ui/auth/auth_strings.dart';
import 'package:mattermost_flutter/src/ui/ui_providers.dart';

/// Adaptive entry point for Mattermost SSO and token login. It displays auth
/// workflow state; the repository owns the browser itself.
class SsoLoginDialog extends ConsumerStatefulWidget {
  const SsoLoginDialog({super.key});

  @override
  ConsumerState<SsoLoginDialog> createState() => _SsoLoginDialogState();
}

class _SsoLoginDialogState extends ConsumerState<SsoLoginDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
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
                onTokenLogin: ref
                    .read(authControllerProvider.notifier)
                    .chooseTokenLogin,
              ),
              AuthPhase.enteringToken => _TokenForm(
                controller: _tokenController,
                failure: auth.failure,
                onSubmit: _authenticateWithToken,
                onBack: ref
                    .read(authControllerProvider.notifier)
                    .returnToMethodChooser,
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

  void _authenticateWithToken() {
    final String token = _tokenController.text;
    _tokenController.clear();
    unawaited(
      ref.read(authControllerProvider.notifier).authenticateWithToken(token),
    );
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
  Widget build(BuildContext context) => Column(
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
      if (failure != null) ...<Widget>[
        const SizedBox(height: 16),
        _FailureMessage(failure!),
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
          if (failure != null && hasServerToRetry)
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

class _SsoChooser extends StatelessWidget {
  const _SsoChooser({
    required this.auth,
    required this.onAuthenticate,
    required this.onChangeServer,
    required this.onTokenLogin,
  });

  final AuthState auth;
  final ValueChanged<SsoProvider> onAuthenticate;
  final VoidCallback onChangeServer;
  final VoidCallback onTokenLogin;

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
      Semantics(
        button: true,
        label: AuthStrings.loginWithToken,
        child: OutlinedButton(
          onPressed: onTokenLogin,
          child: const Text(AuthStrings.loginWithToken),
        ),
      ),
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

class _TokenForm extends StatelessWidget {
  const _TokenForm({
    required this.controller,
    required this.failure,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController controller;
  final AuthFailureKind? failure;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const Text(AuthStrings.tokenTitle, style: TextStyle(fontSize: 22)),
      const SizedBox(height: 12),
      const Text(AuthStrings.tokenDescription),
      const SizedBox(height: 20),
      TextField(
        key: const ValueKey<String>('mattermost-access-token'),
        controller: controller,
        autofocus: true,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        autofillHints: const <String>[AutofillHints.password],
        decoration: const InputDecoration(
          labelText: AuthStrings.tokenLabel,
          hintText: AuthStrings.tokenHint,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
      if (failure != null) ...<Widget>[
        const SizedBox(height: 16),
        _FailureMessage(failure!),
      ],
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          TextButton(onPressed: onBack, child: const Text(AuthStrings.back)),
          FilledButton(
            onPressed: onSubmit,
            child: const Text(AuthStrings.signIn),
          ),
        ],
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage(this.failure);

  final AuthFailureKind failure;

  @override
  Widget build(BuildContext context) => Text(switch (failure) {
    AuthFailureKind.invalidCredentials => AuthStrings.invalidCredentials,
    AuthFailureKind.network => AuthStrings.networkError,
    AuthFailureKind.invalidServer => AuthStrings.invalidInput,
    AuthFailureKind.storage => AuthStrings.storageError,
    AuthFailureKind.ssoUnavailable => AuthStrings.ssoUnavailable,
    AuthFailureKind.browserUnavailable => AuthStrings.browserUnavailable,
    AuthFailureKind.tokenMissing => AuthStrings.tokenMissing,
    AuthFailureKind.sessionExpired => AuthStrings.sessionExpired,
    AuthFailureKind.cancelled => '',
    AuthFailureKind.ssoFailed ||
    AuthFailureKind.invalidResponse => AuthStrings.ssoFailed,
  }, style: TextStyle(color: Theme.of(context).colorScheme.error));
}
