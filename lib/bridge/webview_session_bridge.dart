import 'dart:convert';

import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Holds a reference to the live WebView controller for session injection.
/// Registered from [WebViewScreen] on creation — contains no auth logic.
abstract final class WebViewSessionBridge {
  static InAppWebViewController? _controller;

  static void attach(InAppWebViewController controller) {
    _controller = controller;
  }

  static void detach() {
    _controller = null;
  }

  static Future<void> injectAccessToken(String accessToken) async {
    final controller = _controller;
    if (controller == null) return;

    final key = jsonEncode(AppConfig.sessionStorageKey);
    final value = jsonEncode(accessToken);
    await controller.evaluateJavascript(
      source: 'localStorage.setItem($key, $value);',
    );
  }

  /// Injects session tokens and loads the dashboard URL via the WebView controller.
  static Future<void> injectAccessTokenAndNavigateToDashboard(
    String accessToken,
  ) async {
    final controller = _controller;
    if (controller == null) {
      debugPrint('SESSION INJECT: skipped — WebView controller not attached');
      return;
    }

    final tokenPreview = accessToken.length > 20
        ? accessToken.substring(0, 20)
        : accessToken;
    debugPrint('SESSION INJECT: token=$tokenPreview');

    final base44Key = jsonEncode(AppConfig.sessionStorageKey);
    final tokenKey = jsonEncode(AppConfig.legacyTokenStorageKey);
    final value = jsonEncode(accessToken);

    await controller.evaluateJavascript(
      source: 'localStorage.setItem($base44Key, $value);'
          'localStorage.setItem($tokenKey, $value);',
    );

    debugPrint('NAVIGATE TO: dashboard (${AppConfig.dashboardUrl})');
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConfig.dashboardUrl)),
    );
  }

  static Future<void> navigateTo(String url) async {
    debugPrint('NAVIGATE TO: $url');
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  static Future<void> notifySubscriptionUpdated() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.evaluateJavascript(
      source: "window.dispatchEvent(new Event('subscriptionUpdated'));",
    );
    await navigateTo(AppConfig.dashboardUrl);
  }

  static Future<void> clearSession() async {
    await _controller?.evaluateJavascript(source: 'localStorage.clear();');
  }
}
