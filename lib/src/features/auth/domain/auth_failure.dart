enum AuthFailureKind { invalidCredentials, network, invalidResponse, storage }

final class AuthFailure implements Exception {
  const AuthFailure(this.kind);

  final AuthFailureKind kind;
}
