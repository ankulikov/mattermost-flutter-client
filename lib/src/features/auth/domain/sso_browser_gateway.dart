import 'package:mattermost_flutter/src/features/auth/domain/sso_provider.dart';

/// Starts one interactive SSO attempt in a browser controlled by the app.
///
/// A successful result contains a short-lived session token. Callers must pass
/// it straight to the auth repository and must never place it in UI state.
abstract interface class SsoBrowserGateway {
  Future<SsoBrowserResult> authenticate({
    required Uri serverUrl,
    required SsoProvider provider,
  });

  /// Stops an in-progress browser attempt and clears its Mattermost cookies.
  Future<void> cancel();
}

sealed class SsoBrowserResult {
  const SsoBrowserResult();
}

final class SsoBrowserSuccess extends SsoBrowserResult {
  const SsoBrowserSuccess(this.sessionToken);

  /// Secret material. Keep it only for the immediate repository hand-off.
  final String sessionToken;
}

final class SsoBrowserFailure extends SsoBrowserResult {
  const SsoBrowserFailure(this.kind);

  final SsoBrowserFailureKind kind;
}

enum SsoBrowserFailureKind {
  cancelled,
  browserUnavailable,
  invalidServer,
  unsafeNavigation,
  popupBlocked,
  loadingFailed,
  tokenMissing,
  cookieStore,
}
