import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';
import 'package:mattermost_flutter/src/domain/models/auth_session.dart';
import 'package:mattermost_flutter/src/domain/models/authentication_methods.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/policies/normalize_server_url.dart';
import 'package:mattermost_flutter/src/domain/repositories/auth_repository.dart';

enum AuthPhase {
  signedOut,
  restoring,
  discoveringServer,
  choosingSso,
  enteringToken,
  enteringPassword,
  authenticatingInBrowser,
  validatingToken,
  validatingPassword,
  signedIn,
}

/// Presentation-only state. It intentionally carries no token or browser data.
final class AuthState {
  const AuthState({
    this.phase = AuthPhase.signedOut,
    this.session,
    this.serverUrl,
    this.ssoOptions = const <SsoOption>[],
    this.passwordLoginEnabled = false,
    this.failure,
  });

  final AuthPhase phase;
  final AuthSession? session;
  final Uri? serverUrl;
  final List<SsoOption> ssoOptions;
  final bool passwordLoginEnabled;
  final AuthFailureKind? failure;
}

/// UI state machine for authentication. Public discovery and browser hand-off
/// are repository commands, so the controller depends on no SSO services.
final class AuthController extends Notifier<AuthState> {
  AuthController(this._repositoryProvider);

  final Provider<AuthRepository> _repositoryProvider;
  int _attemptId = 0;
  String? _lastDiscoveryAddress;

  @override
  AuthState build() {
    final AuthRepository repository = ref.read(_repositoryProvider);
    ref.onDispose(() {
      _attemptId += 1;
      unawaited(repository.cancelSsoAuthentication().catchError((_) {}));
    });
    return const AuthState();
  }

  Future<void> restore() async {
    if (state.phase != AuthPhase.signedOut) return;
    final int attemptId = ++_attemptId;
    state = const AuthState(phase: AuthPhase.restoring);
    try {
      final AuthSession? session = await ref
          .read(_repositoryProvider)
          .restoreSession();
      if (!_isCurrent(attemptId)) return;
      state = session == null
          ? const AuthState()
          : AuthState(phase: AuthPhase.signedIn, session: session);
    } on AuthFailure catch (error) {
      if (!_isCurrent(attemptId)) return;
      state = AuthState(failure: error.kind);
    }
  }

  Future<void> discoverServer(String rawServerUrl) async {
    final List<Uri> serverUrls;
    try {
      serverUrls = const NormalizeServerUrl().candidates(rawServerUrl);
    } on AuthFailure catch (error) {
      state = AuthState(failure: error.kind);
      return;
    }

    final int attemptId = ++_attemptId;
    _lastDiscoveryAddress = rawServerUrl;
    for (int index = 0; index < serverUrls.length; index += 1) {
      final Uri serverUrl = serverUrls[index];
      state = AuthState(
        phase: AuthPhase.discoveringServer,
        serverUrl: serverUrl,
      );
      try {
        final AuthenticationMethods methods = await ref
            .read(_repositoryProvider)
            .discoverAuthenticationMethods(serverUrl: serverUrl);
        if (!_isCurrent(attemptId)) return;
        state = AuthState(
          phase: AuthPhase.choosingSso,
          serverUrl: serverUrl,
          ssoOptions: methods.ssoOptions,
          passwordLoginEnabled: methods.passwordLoginEnabled,
        );
        return;
      } on AuthFailure catch (error) {
        if (!_isCurrent(attemptId)) return;
        if (error.kind == AuthFailureKind.network &&
            index < serverUrls.length - 1) {
          continue;
        }
        state = AuthState(serverUrl: serverUrl, failure: error.kind);
        return;
      }
    }
  }

  Future<void> retryDiscovery() async {
    final Uri? serverUrl = state.serverUrl;
    if (serverUrl == null) return;
    await discoverServer(_lastDiscoveryAddress ?? serverUrl.toString());
  }

  void changeServer() {
    _attemptId += 1;
    _lastDiscoveryAddress = null;
    state = const AuthState();
  }

  void chooseTokenLogin() {
    final Uri? serverUrl = state.serverUrl;
    if (serverUrl == null) return;
    _attemptId += 1;
    state = AuthState(
      phase: AuthPhase.enteringToken,
      serverUrl: serverUrl,
      ssoOptions: state.ssoOptions,
      passwordLoginEnabled: state.passwordLoginEnabled,
    );
  }

  void returnToMethodChooser() {
    final Uri? serverUrl = state.serverUrl;
    if (serverUrl == null) return;
    _attemptId += 1;
    state = AuthState(
      phase: AuthPhase.choosingSso,
      serverUrl: serverUrl,
      ssoOptions: state.ssoOptions,
      passwordLoginEnabled: state.passwordLoginEnabled,
    );
  }

  Future<void> authenticateWithToken(String token) async {
    final Uri? serverUrl = state.serverUrl;
    final List<SsoOption> options = state.ssoOptions;
    final String normalizedToken = token.trim();
    if (serverUrl == null) return;
    if (normalizedToken.isEmpty) {
      state = AuthState(
        phase: AuthPhase.enteringToken,
        serverUrl: serverUrl,
        ssoOptions: options,
        passwordLoginEnabled: state.passwordLoginEnabled,
        failure: AuthFailureKind.tokenMissing,
      );
      return;
    }

    final int attemptId = ++_attemptId;
    state = AuthState(
      phase: AuthPhase.validatingToken,
      serverUrl: serverUrl,
      ssoOptions: options,
      passwordLoginEnabled: state.passwordLoginEnabled,
    );
    try {
      final AuthSession session = await ref
          .read(_repositoryProvider)
          .authenticateWithSessionToken(
            serverUrl: serverUrl,
            token: normalizedToken,
          );
      if (!_isCurrent(attemptId)) return;
      state = AuthState(phase: AuthPhase.signedIn, session: session);
    } on AuthFailure catch (error) {
      if (_isCurrent(attemptId)) {
        state = AuthState(
          phase: AuthPhase.enteringToken,
          serverUrl: serverUrl,
          ssoOptions: options,
          passwordLoginEnabled: state.passwordLoginEnabled,
          failure: error.kind,
        );
      }
    }
  }

  void choosePasswordLogin() {
    final Uri? serverUrl = state.serverUrl;
    if (serverUrl == null || !state.passwordLoginEnabled) return;
    _attemptId += 1;
    state = AuthState(
      phase: AuthPhase.enteringPassword,
      serverUrl: serverUrl,
      ssoOptions: state.ssoOptions,
      passwordLoginEnabled: true,
    );
  }

  Future<void> authenticateWithPassword({
    required String loginId,
    required String password,
  }) async {
    final Uri? serverUrl = state.serverUrl;
    final List<SsoOption> options = state.ssoOptions;
    final bool passwordLoginEnabled = state.passwordLoginEnabled;
    final String normalizedLoginId = loginId.trim();
    if (serverUrl == null || !passwordLoginEnabled) return;
    if (normalizedLoginId.isEmpty || password.isEmpty) {
      state = AuthState(
        phase: AuthPhase.enteringPassword,
        serverUrl: serverUrl,
        ssoOptions: options,
        passwordLoginEnabled: passwordLoginEnabled,
        failure: AuthFailureKind.credentialsMissing,
      );
      return;
    }

    final int attemptId = ++_attemptId;
    state = AuthState(
      phase: AuthPhase.validatingPassword,
      serverUrl: serverUrl,
      ssoOptions: options,
      passwordLoginEnabled: passwordLoginEnabled,
    );
    try {
      final AuthSession session = await ref
          .read(_repositoryProvider)
          .authenticateWithPassword(
            serverUrl: serverUrl,
            loginId: normalizedLoginId,
            password: password,
          );
      if (!_isCurrent(attemptId)) return;
      state = AuthState(phase: AuthPhase.signedIn, session: session);
    } on AuthFailure catch (error) {
      if (_isCurrent(attemptId)) {
        state = AuthState(
          phase: AuthPhase.enteringPassword,
          serverUrl: serverUrl,
          ssoOptions: options,
          passwordLoginEnabled: passwordLoginEnabled,
          failure: error.kind,
        );
      }
    }
  }

  Future<void> authenticate(SsoProvider provider) async {
    final Uri? serverUrl = state.serverUrl;
    final List<SsoOption> options = state.ssoOptions;
    if (serverUrl == null ||
        !options.any((SsoOption option) => option.provider == provider)) {
      state = AuthState(
        serverUrl: serverUrl,
        ssoOptions: options,
        passwordLoginEnabled: state.passwordLoginEnabled,
        failure: AuthFailureKind.ssoUnavailable,
      );
      return;
    }

    final int attemptId = ++_attemptId;
    state = AuthState(
      phase: AuthPhase.authenticatingInBrowser,
      serverUrl: serverUrl,
      ssoOptions: options,
      passwordLoginEnabled: state.passwordLoginEnabled,
    );
    try {
      final AuthSession session = await ref
          .read(_repositoryProvider)
          .authenticateWithSso(serverUrl: serverUrl, provider: provider);
      if (!_isCurrent(attemptId)) return;
      state = AuthState(phase: AuthPhase.signedIn, session: session);
    } on AuthFailure catch (error) {
      if (_isCurrent(attemptId)) {
        _returnToChooser(
          serverUrl,
          options,
          state.passwordLoginEnabled,
          error.kind,
        );
      }
    }
  }

  Future<void> cancelSso() async {
    final Uri? serverUrl = state.serverUrl;
    final List<SsoOption> options = state.ssoOptions;
    _attemptId += 1;
    if (serverUrl != null) {
      state = AuthState(
        phase: AuthPhase.choosingSso,
        serverUrl: serverUrl,
        ssoOptions: options,
        passwordLoginEnabled: state.passwordLoginEnabled,
      );
    }
    await ref.read(_repositoryProvider).cancelSsoAuthentication();
  }

  Future<void> signOut() async {
    _attemptId += 1;
    await ref.read(_repositoryProvider).signOut();
    state = const AuthState();
  }

  bool _isCurrent(int attemptId) => attemptId == _attemptId;

  void _returnToChooser(
    Uri serverUrl,
    List<SsoOption> options,
    bool passwordLoginEnabled,
    AuthFailureKind? failure,
  ) {
    state = AuthState(
      phase: AuthPhase.choosingSso,
      serverUrl: serverUrl,
      ssoOptions: options,
      passwordLoginEnabled: passwordLoginEnabled,
      failure: failure == AuthFailureKind.cancelled ? null : failure,
    );
  }
}
