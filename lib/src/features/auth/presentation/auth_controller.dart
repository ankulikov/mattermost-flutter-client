import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_failure.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_repository.dart';
import 'package:mattermost_flutter/src/features/auth/domain/auth_session.dart';
import 'package:mattermost_flutter/src/features/auth/domain/authenticate_with_pat.dart';

enum AuthPhase { signedOut, restoring, submitting, signedIn }

final class AuthState {
  const AuthState({
    this.phase = AuthPhase.signedOut,
    this.session,
    this.failure,
  });

  final AuthPhase phase;
  final AuthSession? session;
  final AuthFailureKind? failure;
}

final class AuthController extends Notifier<AuthState> {
  AuthController(this._repositoryProvider);

  final Provider<AuthRepository> _repositoryProvider;

  @override
  AuthState build() => const AuthState();

  Future<void> restore() async {
    if (state.phase != AuthPhase.signedOut) return;
    state = const AuthState(phase: AuthPhase.restoring);
    try {
      final AuthSession? session = await ref
          .read(_repositoryProvider)
          .restoreSession();
      state = session == null
          ? const AuthState()
          : AuthState(phase: AuthPhase.signedIn, session: session);
    } on AuthFailure catch (error) {
      state = AuthState(failure: error.kind);
    }
  }

  Future<bool> authenticate({
    required String serverUrl,
    required String token,
  }) async {
    state = const AuthState(phase: AuthPhase.submitting);
    try {
      final AuthSession session = await AuthenticateWithPat(
        ref.read(_repositoryProvider),
      )(serverUrl: serverUrl, token: token);
      state = AuthState(phase: AuthPhase.signedIn, session: session);
      return true;
    } on AuthFailure catch (error) {
      state = AuthState(failure: error.kind);
      return false;
    }
  }

  Future<void> signOut() async {
    await ref.read(_repositoryProvider).signOut();
    state = const AuthState();
  }
}
