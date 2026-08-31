import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mattermost_flutter/src/data/logging/auth_diagnostics.dart';
import 'package:mattermost_flutter/src/data/platform/sso_browser_policy.dart';
import 'package:mattermost_flutter/src/domain/models/sso_browser_result.dart';
import 'package:mattermost_flutter/src/domain/models/sso_provider.dart';
import 'package:mattermost_flutter/src/domain/services/sso_browser_gateway.dart';

/// Builds settings that keep the WebView and the plugin Cookie Manager on the
/// same native cookie store.
///
/// On Apple platforms `incognito: true` selects a non-persistent
/// `WKWebsiteDataStore` that `CookieManager.instance()` cannot inspect. On
/// Android the plugin implements incognito by clearing the global cookie store.
/// Scoped Mattermost-cookie cleanup before and after every attempt provides the
/// required session isolation without either platform-specific failure mode.
@visibleForTesting
InAppWebViewSettings buildSsoWebViewSettings() => InAppWebViewSettings(
  allowContentAccess: false,
  allowFileAccess: false,
  allowFileAccessFromFileURLs: false,
  allowUniversalAccessFromFileURLs: false,
  cacheEnabled: false,
  incognito: false,
  javaScriptCanOpenWindowsAutomatically: false,
  supportMultipleWindows: false,
  useShouldOverrideUrlLoading: true,
);

/// Native WebView implementation of [SsoBrowserGateway].
///
/// It deliberately uses the platform Cookie Manager. It never evaluates
/// JavaScript, reads a callback URL for credentials, or exposes cookies to UI.
final class InAppWebViewSsoBrowserGateway implements SsoBrowserGateway {
  InAppWebViewSsoBrowserGateway({
    CookieManager? cookieManager,
    AuthDiagnostics? diagnostics,
  }) : _cookieManager = cookieManager,
       _diagnostics = diagnostics ?? AuthDiagnostics();

  CookieManager? _cookieManager;
  final AuthDiagnostics _diagnostics;
  _NativeSsoAttempt? _activeAttempt;
  int _nextAttemptId = 0;

  @override
  Future<SsoBrowserResult> authenticate({
    required Uri serverUrl,
    required SsoProvider provider,
  }) async {
    _diagnostics.event('sso.authenticate.requested', <String, Object?>{
      'provider': provider.name,
      'server': AuthDiagnostics.safeUri(serverUrl),
      'platform': defaultTargetPlatform.name,
      'is_web': kIsWeb,
    });
    if (kIsWeb) {
      // Flutter Web cannot safely inspect cross-origin HttpOnly cookies.
      _diagnostics.event('sso.authenticate.rejected', <String, Object?>{
        'reason': SsoBrowserFailureKind.browserUnavailable.name,
      });
      return const SsoBrowserFailure(SsoBrowserFailureKind.browserUnavailable);
    }
    if (!SsoBrowserPolicy.isValidServerUrl(serverUrl)) {
      _diagnostics.event('sso.authenticate.rejected', <String, Object?>{
        'reason': SsoBrowserFailureKind.invalidServer.name,
      });
      return const SsoBrowserFailure(SsoBrowserFailureKind.invalidServer);
    }

    await cancel();
    final CookieManager cookieManager = _cookieManager ??=
        CookieManager.instance();
    final _NativeSsoAttempt attempt = _NativeSsoAttempt(
      attemptId: ++_nextAttemptId,
      cookieManager: cookieManager,
      diagnostics: _diagnostics,
      serverUrl: serverUrl,
      startUrl: SsoBrowserPolicy.startUrl(
        serverUrl: serverUrl,
        provider: provider,
      ),
    );
    _activeAttempt = attempt;

    final SsoBrowserResult result = await attempt.start();
    if (identical(_activeAttempt, attempt)) {
      _activeAttempt = null;
    }
    _diagnostics.event('sso.authenticate.completed', <String, Object?>{
      'attempt_id': attempt.attemptId,
      'result': _resultName(result),
    });
    return result;
  }

  @override
  Future<void> cancel() async {
    final _NativeSsoAttempt? attempt = _activeAttempt;
    if (attempt == null) {
      _diagnostics.event('sso.cancel.ignored', const <String, Object?>{
        'reason': 'no_active_attempt',
      });
      return;
    }
    _activeAttempt = null;
    _diagnostics.event('sso.cancel.requested', <String, Object?>{
      'attempt_id': attempt.attemptId,
    });
    await attempt.cancel();
  }

  static String _resultName(SsoBrowserResult result) => switch (result) {
    SsoBrowserSuccess() => 'success',
    SsoBrowserFailure(:final SsoBrowserFailureKind kind) => kind.name,
  };
}

final class _NativeSsoAttempt {
  _NativeSsoAttempt({
    required this.attemptId,
    required CookieManager cookieManager,
    required AuthDiagnostics diagnostics,
    required this.serverUrl,
    required this.startUrl,
  }) : _cookieManager = cookieManager,
       _diagnostics = diagnostics,
       _browser = _SsoInAppBrowser();

  final int attemptId;
  final CookieManager _cookieManager;
  final AuthDiagnostics _diagnostics;
  final Uri serverUrl;
  final Uri startUrl;
  final _SsoInAppBrowser _browser;
  final Completer<SsoBrowserResult> _result = Completer<SsoBrowserResult>();

  bool _isCompleting = false;
  bool _isCheckingCookie = false;

  Future<SsoBrowserResult> start() async {
    _browser.attempt = this;
    _log('sso.attempt.started', <String, Object?>{
      'server': AuthDiagnostics.safeUri(serverUrl),
      'start_url': AuthDiagnostics.safeUri(startUrl),
    });
    try {
      final int deletedCookies = await _clearMattermostCookies();
      _log('sso.cookies.cleared_before_start', <String, Object?>{
        'deleted_count': deletedCookies,
      });
    } on Object catch (error) {
      _logException('sso.cookies.clear_before_start_failed', error);
      await _finish(const SsoBrowserFailure(SsoBrowserFailureKind.cookieStore));
      return _result.future;
    }
    if (_isCompleting) {
      return _result.future;
    }

    try {
      _log('sso.browser.open_requested');
      await _browser.openUrlRequest(
        urlRequest: URLRequest(url: WebUri.uri(startUrl)),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            shouldCloseOnBackButtonPressed: true,
            hideUrlBar: true,
          ),
          webViewSettings: buildSsoWebViewSettings(),
        ),
      );
      _log('sso.browser.open_completed');
      if (_isCompleting) {
        try {
          await _browser.close();
        } on Object catch (error) {
          _logException('sso.browser.close_after_completion_failed', error);
          // The attempt has already produced its terminal result.
        }
      }
    } on Object catch (error) {
      _logException('sso.browser.open_failed', error);
      await _finish(
        const SsoBrowserFailure(SsoBrowserFailureKind.loadingFailed),
      );
    }
    return _result.future;
  }

  Future<void> cancel() =>
      _finish(const SsoBrowserFailure(SsoBrowserFailureKind.cancelled));

  Future<NavigationActionPolicy> decideNavigation(Uri? navigationUrl) async {
    if (_isCompleting || navigationUrl == null) {
      _log('sso.navigation.cancelled', <String, Object?>{
        'reason': _isCompleting ? 'attempt_completing' : 'missing_url',
        'url': AuthDiagnostics.safeUri(navigationUrl),
      });
      return NavigationActionPolicy.CANCEL;
    }
    final bool allowed = SsoBrowserPolicy.isAllowedNavigation(navigationUrl);
    _log('sso.navigation.requested', <String, Object?>{
      'url': AuthDiagnostics.safeUri(navigationUrl),
      'allowed': allowed,
      'expected_return': SsoBrowserPolicy.isExpectedReturn(
        serverUrl: serverUrl,
        navigationUrl: navigationUrl,
      ),
    });
    if (!allowed) {
      unawaited(
        _finish(
          const SsoBrowserFailure(SsoBrowserFailureKind.unsafeNavigation),
        ),
      );
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  void navigationStarted(Uri? navigationUrl) {
    _log('sso.navigation.started', <String, Object?>{
      'url': AuthDiagnostics.safeUri(navigationUrl),
      'expected_return':
          navigationUrl != null &&
          SsoBrowserPolicy.isExpectedReturn(
            serverUrl: serverUrl,
            navigationUrl: navigationUrl,
          ),
    });
  }

  void navigationFinished(Uri? navigationUrl) {
    final bool expectedReturn =
        navigationUrl != null &&
        SsoBrowserPolicy.isExpectedReturn(
          serverUrl: serverUrl,
          navigationUrl: navigationUrl,
        );
    _log('sso.navigation.finished', <String, Object?>{
      'url': AuthDiagnostics.safeUri(navigationUrl),
      'expected_return': expectedReturn,
      'cookie_check_active': _isCheckingCookie,
      'attempt_completing': _isCompleting,
    });
    if (_isCompleting ||
        _isCheckingCookie ||
        navigationUrl == null ||
        !expectedReturn) {
      return;
    }
    _log('sso.cookie_check.started', <String, Object?>{
      'trigger_url': AuthDiagnostics.safeUri(navigationUrl),
    });
    unawaited(_readSessionCookie());
  }

  void loadingFailed({
    required Uri? url,
    required String source,
    required int code,
  }) {
    _log('sso.navigation.failed', <String, Object?>{
      'url': AuthDiagnostics.safeUri(url),
      'source': source,
      'code': code,
    });
    if (!_isCompleting) {
      unawaited(
        _finish(const SsoBrowserFailure(SsoBrowserFailureKind.loadingFailed)),
      );
    }
  }

  void browserClosed() {
    _log('sso.browser.closed', <String, Object?>{
      'attempt_completing': _isCompleting,
    });
    if (!_isCompleting) {
      unawaited(
        _finish(const SsoBrowserFailure(SsoBrowserFailureKind.cancelled)),
      );
    }
  }

  void popupRequested() {
    _log('sso.popup.blocked');
    if (!_isCompleting) {
      unawaited(
        _finish(const SsoBrowserFailure(SsoBrowserFailureKind.popupBlocked)),
      );
    }
  }

  Future<void> _readSessionCookie() async {
    _isCheckingCookie = true;
    try {
      for (int attempt = 0; attempt != 3; attempt += 1) {
        final List<Cookie> nativeCookies = await _cookieManager.getCookies(
          url: WebUri.uri(serverUrl),
        );
        final List<SsoBrowserCookie> policyCookies = nativeCookies
            .map(_toPolicyCookie)
            .toList(growable: false);
        final String? token = SsoBrowserPolicy.sessionTokenFromCookies(
          serverUrl: serverUrl,
          cookies: policyCookies,
        );
        _log('sso.cookie_check.poll', <String, Object?>{
          'poll': attempt + 1,
          'cookie_count': policyCookies.length,
          'session_cookie_count': policyCookies
              .where(
                (SsoBrowserCookie cookie) =>
                    cookie.name == SsoBrowserPolicy.sessionCookieName,
              )
              .length,
          'usable_session_cookie': token != null,
        });
        if (token != null) {
          await _finish(SsoBrowserSuccess(token));
          return;
        }
        if (attempt != 2) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      _log('sso.cookie_check.exhausted');
      await _finish(
        const SsoBrowserFailure(SsoBrowserFailureKind.tokenMissing),
      );
    } on Object catch (error) {
      _logException('sso.cookie_check.failed', error);
      await _finish(const SsoBrowserFailure(SsoBrowserFailureKind.cookieStore));
    } finally {
      _isCheckingCookie = false;
    }
  }

  Future<void> _finish(SsoBrowserResult result) async {
    if (_isCompleting) {
      return;
    }
    _isCompleting = true;
    _log('sso.attempt.finishing', <String, Object?>{
      'result': _resultName(result),
    });

    try {
      await _browser.close();
    } on Object catch (error) {
      _logException('sso.browser.close_failed', error);
      // Closing an already-dismissed native browser is harmless.
    }

    SsoBrowserResult finalResult = result;
    try {
      final int deletedCookies = await _clearMattermostCookies();
      _log('sso.cookies.cleared_after_finish', <String, Object?>{
        'deleted_count': deletedCookies,
      });
    } on Object catch (error) {
      _logException('sso.cookies.clear_after_finish_failed', error);
      finalResult = const SsoBrowserFailure(SsoBrowserFailureKind.cookieStore);
    }
    if (!_result.isCompleted) {
      _log('sso.attempt.completed', <String, Object?>{
        'result': _resultName(finalResult),
      });
      _result.complete(finalResult);
    }
  }

  Future<int> _clearMattermostCookies() async {
    final WebUri url = WebUri.uri(serverUrl);
    final List<Cookie> cookies = await _cookieManager.getCookies(url: url);
    var deletedCount = 0;
    for (final Cookie cookie in cookies) {
      if (!SsoBrowserPolicy.cookiesToClear.contains(cookie.name)) {
        continue;
      }
      final bool didDelete = await _cookieManager.deleteCookie(
        url: url,
        name: cookie.name,
        path: cookie.path ?? '/',
        domain: cookie.domain,
      );
      if (!didDelete) {
        throw StateError('Could not clear SSO browser cookie.');
      }
      deletedCount += 1;
    }
    return deletedCount;
  }

  SsoBrowserCookie _toPolicyCookie(Cookie cookie) {
    final dynamic value = cookie.value;
    return SsoBrowserCookie(
      name: cookie.name,
      value: value is String ? value : '',
      domain: cookie.domain,
      path: cookie.path,
    );
  }

  void _log(String event, [Map<String, Object?> fields = const {}]) {
    _diagnostics.event(event, <String, Object?>{
      'attempt_id': attemptId,
      ...fields,
    });
  }

  void _logException(String event, Object error) {
    _log(event, <String, Object?>{'error_type': error.runtimeType.toString()});
  }

  static String _resultName(SsoBrowserResult result) => switch (result) {
    SsoBrowserSuccess() => 'success',
    SsoBrowserFailure(:final SsoBrowserFailureKind kind) => kind.name,
  };
}

final class _SsoInAppBrowser extends InAppBrowser {
  _NativeSsoAttempt? attempt;

  @override
  void onExit() => attempt?.browserClosed();

  @override
  void onLoadError(Uri? url, int code, String message) =>
      attempt?.loadingFailed(url: url, source: 'load_error', code: code);

  @override
  void onLoadHttpError(Uri? url, int statusCode, String description) =>
      attempt?.loadingFailed(url: url, source: 'http_error', code: statusCode);

  @override
  void onLoadStart(WebUri? url) => attempt?.navigationStarted(url);

  @override
  void onLoadStop(WebUri? url) => attempt?.navigationFinished(url);

  @override
  Future<bool?>? onCreateWindow(CreateWindowAction createWindowAction) async {
    attempt?.popupRequested();
    return false;
  }

  @override
  Future<PermissionResponse?>? onPermissionRequest(
    PermissionRequest permissionRequest,
  ) async => PermissionResponse();

  @override
  Future<GeolocationPermissionShowPromptResponse?>?
  androidOnGeolocationPermissionsShowPrompt(String origin) async =>
      GeolocationPermissionShowPromptResponse(allow: false, origin: origin);

  @override
  Future<NavigationActionPolicy?>? shouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) => attempt?.decideNavigation(navigationAction.request.url);
}
