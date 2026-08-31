import 'package:mattermost_flutter/src/domain/models/sso_browser_result.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';

/// Starts one interactive SSO attempt in a platform browser controlled by the
/// app. The browser adapter never exposes cookies to UI.
abstract interface class SsoBrowserGateway {
  Future<SsoBrowserResult> authenticate({
    required Uri serverUrl,
    required SsoProvider provider,
  });

  /// Stops an in-progress attempt and clears its server-scoped cookies.
  Future<void> cancel();
}
