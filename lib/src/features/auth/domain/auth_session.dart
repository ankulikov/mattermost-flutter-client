final class AuthSession {
  const AuthSession({
    required this.serverUrl,
    required this.userId,
    required this.username,
  });

  final Uri serverUrl;
  final String userId;
  final String username;

  String get accountId => serverUrl.toString();

  /// Separates durable tenant data for different signed-in users on one server.
  String get durableDataScopeId => '${serverUrl.toString()}|user:$userId';
}
