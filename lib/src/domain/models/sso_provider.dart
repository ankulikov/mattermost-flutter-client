/// An interactive sign-on provider advertised by a Mattermost server.
enum SsoProvider { saml, openId }

/// One interactive sign-on method advertised by a Mattermost server's public
/// configuration.
final class SsoOption {
  const SsoOption({required this.provider, required this.displayLabel});

  final SsoProvider provider;
  final String displayLabel;
}
