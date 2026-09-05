enum AuthFailureKind {
  invalidServer,
  ssoUnavailable,
  browserUnavailable,
  cancelled,
  ssoFailed,
  tokenMissing,
  credentialsMissing,
  invalidCredentials,
  sessionExpired,
  network,
  invalidResponse,
  storage,
}

final class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;
}
