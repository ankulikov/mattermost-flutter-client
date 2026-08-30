import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/normalize_server_url.dart';
import 'package:mattermost_flutter/src/features/auth/domain/server_sso_discovery.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

enum AuthPhase {
  signedOut,
  restoring,
  discoveringServer,
  choosingSso,
  enteringToken,
  authenticatingInBrowser,
  validatingToken,
  signedIn,
}

final class AuthState {
  const AuthState({
    this.phase = AuthPhase.signedOut,
    this.session,
    this.serverUrl,
    this.ssoOptions = const <SsoOption>[],
    this.failure,
  });

  final AuthPhase phase;
  final AuthSession? session;
  final Uri? serverUrl;
  final List<SsoOption> ssoOptions;
  final AuthFailureKind? failure;
}

/// Coordinates authentication without allowing a secret to enter [AuthState].
final class AuthController extends Notifier<AuthState> {
  AuthController(
    this._repositoryProvider,
    this._discoveryProvider,
    this._browserGatewayProvider,
  );

  final Provider<AuthRepository> _repositoryProvider;
  final Provider<ServerSsoDiscovery> _discoveryProvider;
  final Provider<SsoBrowserGateway> _browserGatewayProvider;
  int _attemptId = 0;

  @override
  AuthState build() {
    final SsoBrowserGateway browserGateway = ref.read(_browserGatewayProvider);
    ref.onDispose(() {
      _attemptId += 1;
      // The adapter owns native resources. It handles cancellation failures
      // internally, and a provider disposal cannot await a Future.
      unawaited(browserGateway.cancel().catchError((_) {}));
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
    final Uri serverUrl;
    try {
      serverUrl = const NormalizeServerUrl()(rawServerUrl);
    } on AuthFailure catch (error) {
      state = AuthState(failure: error.kind);
      return;
    }

    final int attemptId = ++_attemptId;
    state = AuthState(phase: AuthPhase.discoveringServer, serverUrl: serverUrl);
    try {
      final List<SsoOption> options = await ref
          .read(_discoveryProvider)
          .discover(serverUrl);
      if (!_isCurrent(attemptId)) return;
      state = AuthState(
        phase: AuthPhase.choosingSso,
        serverUrl: serverUrl,
        ssoOptions: options,
      );
    } on AuthFailure catch (error) {
      if (!_isCurrent(attemptId)) return;
      state = AuthState(serverUrl: serverUrl, failure: error.kind);
    }
  }

  Future<void> retryDiscovery() async {
    final Uri? serverUrl = state.serverUrl;
    if (serverUrl == null) return;
    await discoverServer(serverUrl.toString());
  }

  void changeServer() {
    _attemptId += 1;
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
        failure: AuthFailureKind.tokenMissing,
      );
      return;
    }

    final int attemptId = ++_attemptId;
    state = AuthState(
      phase: AuthPhase.validatingToken,
      serverUrl: serverUrl,
      ssoOptions: options,
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
        failure: AuthFailureKind.ssoUnavailable,
      );
      return;
    }

    final int attemptId = ++_attemptId;
    state = AuthState(
      phase: AuthPhase.authenticatingInBrowser,
      serverUrl: serverUrl,
      ssoOptions: options,
    );
    final SsoBrowserResult browserResult;
    try {
      browserResult = await ref
          .read(_browserGatewayProvider)
          .authenticate(serverUrl: serverUrl, provider: provider);
    } on Object {
      if (_isCurrent(attemptId)) {
        _returnToChooser(serverUrl, options, AuthFailureKind.ssoFailed);
      }
      return;
    }
    if (!_isCurrent(attemptId)) return;

    switch (browserResult) {
      case SsoBrowserSuccess(:final String sessionToken):
        state = AuthState(
          phase: AuthPhase.validatingToken,
          serverUrl: serverUrl,
          ssoOptions: options,
        );
        try {
          final AuthSession session = await ref
              .read(_repositoryProvider)
              .authenticateWithSessionToken(
                serverUrl: serverUrl,
                token: sessionToken,
              );
          if (!_isCurrent(attemptId)) return;
          state = AuthState(phase: AuthPhase.signedIn, session: session);
        } on AuthFailure catch (error) {
          if (_isCurrent(attemptId)) {
            _returnToChooser(serverUrl, options, error.kind);
          }
        }
      case SsoBrowserFailure(:final SsoBrowserFailureKind kind):
        _returnToChooser(
          serverUrl,
          options,
          kind == SsoBrowserFailureKind.cancelled
              ? null
              : _browserFailure(kind),
        );
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
      );
    }
    await ref.read(_browserGatewayProvider).cancel();
  }

  Future<void> signOut() async {
    _attemptId += 1;
    await ref.read(_browserGatewayProvider).cancel();
    await ref.read(_repositoryProvider).signOut();
    state = const AuthState();
  }

  bool _isCurrent(int attemptId) => attemptId == _attemptId;

  void _returnToChooser(
    Uri serverUrl,
    List<SsoOption> options,
    AuthFailureKind? failure,
  ) {
    state = AuthState(
      phase: AuthPhase.choosingSso,
      serverUrl: serverUrl,
      ssoOptions: options,
      failure: failure,
    );
  }

  AuthFailureKind _browserFailure(SsoBrowserFailureKind kind) => switch (kind) {
    SsoBrowserFailureKind.browserUnavailable =>
      AuthFailureKind.browserUnavailable,
    SsoBrowserFailureKind.invalidServer => AuthFailureKind.invalidServer,
    SsoBrowserFailureKind.tokenMissing => AuthFailureKind.tokenMissing,
    SsoBrowserFailureKind.cancelled => AuthFailureKind.cancelled,
    SsoBrowserFailureKind.unsafeNavigation ||
    SsoBrowserFailureKind.popupBlocked ||
    SsoBrowserFailureKind.loadingFailed ||
    SsoBrowserFailureKind.cookieStore => AuthFailureKind.ssoFailed,
  };
}
