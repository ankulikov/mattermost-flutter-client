import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_controller.dart';
import 'package:mattermost_flutter/src/features/auth/presentation/auth_strings.dart';

class PatLoginDialog extends ConsumerStatefulWidget {
  const PatLoginDialog({super.key});

  @override
  ConsumerState<PatLoginDialog> createState() => _PatLoginDialogState();
}

class _PatLoginDialogState extends ConsumerState<PatLoginDialog> {
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _obscureToken = true;

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authControllerProvider);
    final bool submitting = auth.phase == AuthPhase.submitting;
    return AlertDialog(
      title: const Text(AuthStrings.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(AuthStrings.description),
              const SizedBox(height: 20),
              TextFormField(
                controller: _serverController,
                enabled: !submitting,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: AuthStrings.serverLabel,
                  hintText: AuthStrings.serverHint,
                  border: OutlineInputBorder(),
                ),
                validator: (String? value) =>
                    value == null || value.trim().isEmpty
                    ? AuthStrings.invalidInput
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tokenController,
                enabled: !submitting,
                obscureText: _obscureToken,
                enableSuggestions: false,
                autocorrect: false,
                onFieldSubmitted: submitting ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: AuthStrings.tokenLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscureToken
                        ? AuthStrings.showToken
                        : AuthStrings.hideToken,
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                    icon: Icon(
                      _obscureToken ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (String? value) =>
                    value == null || value.trim().isEmpty
                    ? AuthStrings.invalidInput
                    : null,
              ),
              if (auth.failure != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _failureMessage(auth.failure!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
          child: const Text(AuthStrings.cancel),
        ),
        FilledButton(
          onPressed: submitting ? null : _submit,
          child: submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(AuthStrings.connect),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final bool authenticated = await ref
        .read(authControllerProvider.notifier)
        .authenticate(
          serverUrl: _serverController.text,
          token: _tokenController.text,
        );
    if (authenticated && mounted) Navigator.of(context).pop();
  }

  String _failureMessage(AuthFailureKind failure) => switch (failure) {
    AuthFailureKind.invalidCredentials => AuthStrings.invalidCredentials,
    AuthFailureKind.network => AuthStrings.networkError,
    AuthFailureKind.invalidResponse => AuthStrings.invalidInput,
    AuthFailureKind.storage => AuthStrings.storageError,
  };
}
