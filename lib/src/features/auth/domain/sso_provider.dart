enum SsoProvider { saml, openId }

/// One SSO method advertised by a Mattermost server's public configuration.
final class SsoOption {
  const SsoOption({required this.provider, required this.displayLabel});

  final SsoProvider provider;
  final String displayLabel;
}
