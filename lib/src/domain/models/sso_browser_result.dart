/// Typed outcome from the platform-owned interactive sign-on browser.
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
