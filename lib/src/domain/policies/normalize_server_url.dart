import 'package:mattermost_flutter/src/domain/models/auth_failure.dart';

/// Parses and canonicalizes a Mattermost server URL used by authentication.
///
/// A deployment path is preserved and trailing slashes are removed. For a
/// schemeless address, [candidates] supplies the protocol probe order.
final class NormalizeServerUrl {
  const NormalizeServerUrl();

  /// Returns server origins in the order they should be tried.
  ///
  /// Explicit schemes are authoritative, except HTTP is accepted only for
  /// private or local hosts. Schemeless addresses always try HTTPS first and
  /// fall back to HTTP only when the host permits unencrypted traffic.
  List<Uri> candidates(String value) {
    final String trimmed = value.trim();
    final bool hasExplicitScheme = RegExp(
      r'^[a-zA-Z][a-zA-Z0-9+.-]*://',
    ).hasMatch(trimmed);
    final Uri? parsed = Uri.tryParse(
      hasExplicitScheme ? trimmed : 'https://$trimmed',
    );
    if (parsed == null || !_isValidServerUri(parsed)) {
      throw const AuthFailure(AuthFailureKind.invalidServer);
    }

    final Uri normalized = _normalize(parsed);
    if (normalized.scheme == 'http' && !_isHttpAllowedHost(normalized.host)) {
      throw const AuthFailure(AuthFailureKind.insecureProtocol);
    }
    if (hasExplicitScheme) return <Uri>[normalized];

    final Uri http = normalized.replace(scheme: 'http');
    return _isHttpAllowedHost(normalized.host)
        ? <Uri>[normalized, http]
        : <Uri>[normalized];
  }

  /// Returns the preferred origin for a server address.
  Uri call(String value) => candidates(value).first;

  Uri _normalize(Uri parsed) {
    final String path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    return parsed.replace(
      scheme: parsed.scheme.toLowerCase(),
      host: parsed.host.toLowerCase(),
      path: path,
    );
  }

  bool _isValidServerUri(Uri uri) {
    return uri.hasScheme &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.scheme.toLowerCase() == 'https' ||
            uri.scheme.toLowerCase() == 'http');
  }

  bool _isHttpAllowedHost(String host) {
    final String normalizedHost = host.toLowerCase();
    return normalizedHost == 'localhost' ||
        _isAllowedIpv4Address(normalizedHost) ||
        _isAllowedIpv6Address(normalizedHost) ||
        normalizedHost.endsWith('.lan') ||
        normalizedHost.endsWith('.local');
  }

  bool _isAllowedIpv4Address(String host) {
    final List<int>? octets = _ipv4Octets(host);
    if (octets == null) return false;

    final int first = octets[0];
    final int second = octets[1];
    // RFC 1918 private networks: 10.0.0.0/8, 172.16.0.0/12, and
    // 192.168.0.0/16.
    final bool rfc1918Private =
        first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
    // Loopback and link-local addresses are only reachable on the local
    // network: 127.0.0.0/8 and 169.254.0.0/16.
    final bool localOnlyOrLinkLocal =
        first == 127 || (first == 169 && second == 254);
    // RFC 6598 shared address space, 100.64.0.0/10, includes Tailscale CGNAT
    // addresses.
    final bool rfc6598Cgnat = first == 100 && second >= 64 && second <= 127;
    return rfc1918Private || localOnlyOrLinkLocal || rfc6598Cgnat;
  }

  List<int>? _ipv4Octets(String host) {
    final List<String> parts = host.split('.');
    if (parts.length != 4) return null;

    final List<int> octets = <int>[];
    for (final String part in parts) {
      if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) return null;
      final int? octet = int.tryParse(part);
      if (octet == null || octet > 255) return null;
      octets.add(octet);
    }
    return octets;
  }

  bool _isAllowedIpv6Address(String host) {
    final int compression = host.indexOf('::');
    if (compression != host.lastIndexOf('::') ||
        (host.startsWith(':') && !host.startsWith('::')) ||
        (host.endsWith(':') && !host.endsWith('::'))) {
      return false;
    }

    final List<String> parts = host.split(':');
    final List<String> hextets = parts
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (compression == -1 ? hextets.length != 8 : hextets.length > 7) {
      return false;
    }

    for (final String part in hextets) {
      if (!RegExp(r'^[0-9a-f]{1,4}$').hasMatch(part)) return false;
    }

    final String firstHextet = hextets.isEmpty ? '0' : hextets.first;
    final int value = int.parse(firstHextet, radix: 16);
    return value >= 0xfc00 && value <= 0xfdff;
  }
}
