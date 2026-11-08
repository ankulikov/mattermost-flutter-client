import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mattermost_flutter/src/data/platform/in_app_webview_sso_browser_gateway.dart';

void main() {
  final Uri serverUrl = Uri.parse('https://chat.example.com/mattermost');

  test(
    'clears a stale cookie even when its path and domain are unavailable',
    () async {
      final _CookieManagerFake cookieManager = _CookieManagerFake(
        cookies: <Cookie>[
          Cookie(name: 'MMAUTHTOKEN', value: 'stale'),
          Cookie(name: 'MMUSERID', value: 'old-user'),
        ],
      );

      final bool removedAny = await clearSsoBrowserCookies(
        cookieManager: cookieManager,
        serverUrl: serverUrl,
      );

      expect(removedAny, isTrue);
      expect(cookieManager.deleteAllCalls, 1);
      expect(cookieManager.cookies, isEmpty);
      expect(cookieManager.lastReadUrl, WebUri.uri(serverUrl));
    },
  );

  test('an already empty cookie store is a successful cleanup', () async {
    final _CookieManagerFake cookieManager = _CookieManagerFake();

    expect(
      await clearSsoBrowserCookies(
        cookieManager: cookieManager,
        serverUrl: serverUrl,
      ),
      isFalse,
    );
  });

  test('rejects cleanup when the old session cookie remains', () async {
    final _CookieManagerFake cookieManager = _CookieManagerFake(
      cookies: <Cookie>[Cookie(name: 'MMAUTHTOKEN', value: 'stale')],
      clearOnDelete: false,
    );

    await expectLater(
      clearSsoBrowserCookies(
        cookieManager: cookieManager,
        serverUrl: serverUrl,
      ),
      throwsStateError,
    );
  });
}

final class _CookieManagerFake extends Fake implements CookieManager {
  _CookieManagerFake({List<Cookie>? cookies, this.clearOnDelete = true})
    : cookies = cookies ?? <Cookie>[];

  final List<Cookie> cookies;
  final bool clearOnDelete;
  int deleteAllCalls = 0;
  WebUri? lastReadUrl;

  @override
  Future<bool> deleteAllCookies() async {
    deleteAllCalls += 1;
    final bool removedAny = cookies.isNotEmpty;
    if (clearOnDelete) cookies.clear();
    return removedAny;
  }

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? iosBelow11WebViewController,
    InAppWebViewController? webViewController,
  }) async {
    lastReadUrl = url;
    return List<Cookie>.of(cookies);
  }
}
