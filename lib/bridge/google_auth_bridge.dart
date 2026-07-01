import 'dart:convert';

import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Google OAuth for Base44 apps via the system browser.
///
/// Base44 flow (from production URLs):
/// 1. `/login?from_url=…` on the app subdomain
/// 2. → `accounts.google.com/…&redirect_uri=app.base44.com/api/apps/auth/callback&state={domain,from_url,app_id}`
/// 3. → `app.base44.com/api/apps/auth/callback?code&state`
/// 4. → redirect to `from_url` (e.g. `/dashboard`)
///
/// Opening only the Google URL in a Custom Tab breaks session binding. The full
/// login → Google → callback chain must run in one browser context, then the
/// final app URL is loaded back into the WebView.
abstract final class GoogleAuthBridge {
  static bool _authInProgress = false;

  static bool isGoogleOAuthUrl(Uri url) {
    final host = url.host.toLowerCase();
    return host == 'accounts.google.com' ||
        host.endsWith('.accounts.google.com');
  }

  /// Runs Google sign-in in the system browser starting from the Base44 login
  /// page so cookies/session stay consistent through the whole OAuth chain.
  static Future<String?> signInWithGoogle({
    Uri? googleOAuthUrl,
    required InAppWebViewController webViewController,
  }) async {
    if (_authInProgress) return null;
    _authInProgress = true;

    try {
      final fromUrl = await _resolveFromUrl(
        webViewController: webViewController,
        googleOAuthUrl: googleOAuthUrl,
      );
      final fromUri = Uri.parse(fromUrl);
      final loginUrl = AppConfig.loginUri(fromUrl: fromUrl);

      debugPrint('GoogleAuthBridge: opening login flow — $loginUrl');
      debugPrint('GoogleAuthBridge: expecting redirect — $fromUrl');

      return await FlutterWebAuth2.authenticate(
        url: loginUrl.toString(),
        callbackUrlScheme: 'https',
        options: FlutterWebAuth2Options(
          httpsHost: fromUri.host,
          httpsPath: _normalizedPath(fromUri),
        ),
      );
    } on PlatformException catch (error) {
      if (error.code != 'CANCELED') {
        debugPrint('GoogleAuthBridge: sign-in failed — ${error.message}');
      }
      return null;
    } finally {
      _authInProgress = false;
    }
  }

  /// Intercepts Google OAuth navigations that would be blocked inside WebView.
  static Future<NavigationActionPolicy?> interceptNavigation({
    required Uri url,
    required InAppWebViewController webViewController,
    void Function()? onAuthStarted,
    void Function()? onAuthFinished,
  }) async {
    if (!isGoogleOAuthUrl(url)) return null;
    if (_authInProgress) return NavigationActionPolicy.CANCEL;

    onAuthStarted?.call();
    try {
      final resultUrl = await signInWithGoogle(
        googleOAuthUrl: url,
        webViewController: webViewController,
      );
      if (resultUrl != null) {
        await applyCallbackToWebView(
          webViewController: webViewController,
          callbackUrl: resultUrl,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('GoogleAuthBridge: unexpected error — $error');
      debugPrint('$stackTrace');
    } finally {
      onAuthFinished?.call();
    }

    return NavigationActionPolicy.CANCEL;
  }

  /// Loads the post-login URL into the WebView so the app reflects signed-in state.
  static Future<void> applyCallbackToWebView({
    required InAppWebViewController webViewController,
    required String callbackUrl,
  }) async {
    debugPrint('GoogleAuthBridge: loading result in WebView — $callbackUrl');

    await webViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(callbackUrl)),
    );
  }

  static Future<String> _resolveFromUrl({
    required InAppWebViewController webViewController,
    Uri? googleOAuthUrl,
  }) async {
    final stateFromGoogle = googleOAuthUrl != null
        ? _parseOAuthState(googleOAuthUrl)
        : null;
    final fromState = stateFromGoogle?['from_url'];
    if (fromState is String && fromState.isNotEmpty) {
      return fromState;
    }

    final current = await webViewController.getUrl();
    if (current != null) {
      final fromQuery = current.queryParameters['from_url'];
      if (fromQuery != null && fromQuery.isNotEmpty) {
        return fromQuery;
      }
      if (!current.path.contains('login')) {
        return current.toString();
      }
    }

    return '${AppConfig.webUrl}/dashboard';
  }

  static Map<String, dynamic>? _parseOAuthState(Uri googleOAuthUrl) {
    final raw = googleOAuthUrl.queryParameters['state'];
    if (raw == null || raw.isEmpty) return null;

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      try {
        return jsonDecode(Uri.decodeComponent(raw)) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
  }

  static String _normalizedPath(Uri uri) {
    if (uri.path.isEmpty) return '/';
    return uri.path;
  }
}
