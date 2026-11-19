import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';
import 'package:mattermost_flutter/src/domain/models/sso_browser_result.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';

void main() {
  test('macOS does not fall back to the native SSO window', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final result = await InAppWebViewSsoBrowserGateway().authenticate(
      serverUrl: Uri.parse('https://chat.example.com'),
      provider: SsoProvider.openId,
    );

    expect(
      result,
      isA<SsoBrowserFailure>().having(
        (failure) => failure.kind,
        'kind',
        SsoBrowserFailureKind.browserUnavailable,
      ),
    );
  });

  test(
    'uses the Cookie Manager visible store with hardened WebView settings',
    () {
      final InAppWebViewSettings settings = buildSsoWebViewSettings();

      expect(settings.incognito, isFalse);
      expect(settings.cacheEnabled, isFalse);
      expect(settings.allowContentAccess, isFalse);
      expect(settings.allowFileAccess, isFalse);
      expect(settings.allowFileAccessFromFileURLs, isFalse);
      expect(settings.allowUniversalAccessFromFileURLs, isFalse);
      expect(settings.javaScriptCanOpenWindowsAutomatically, isFalse);
      expect(settings.supportMultipleWindows, isFalse);
      expect(settings.useShouldOverrideUrlLoading, isTrue);
    },
  );
}
