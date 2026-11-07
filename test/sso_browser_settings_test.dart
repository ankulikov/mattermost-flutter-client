import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    test('sends safe native browser settings on ${platform.name}', () {
      debugDefaultTargetPlatformOverride = platform;
      final Map<String, dynamic> settings = buildSsoBrowserSettings().toMap();

      expect(settings['hideToolbarTop'], platform == TargetPlatform.macOS);
      expect(settings['hideUrlBar'], isTrue);
      expect(settings['shouldCloseOnBackButtonPressed'], isTrue);
    });
  }

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
