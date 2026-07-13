import 'package:doublecheck_repairs/bridge/webview_session_bridge.dart';

/// In-memory Base44 session state shared across auth and IAP flows.
abstract final class AppSession {
  static String? _base44AccessToken;

  static void setBase44AccessToken(String token) {
    _base44AccessToken = token;
  }

  static void clearBase44AccessToken() {
    _base44AccessToken = null;
  }

  /// Returns the cached token, or reads it from WebView localStorage.
  static Future<String?> resolveBase44AccessToken() async {
    final cached = _base44AccessToken;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final fromStorage = await WebViewSessionBridge.readAccessTokenFromStorage();
    if (fromStorage != null && fromStorage.isNotEmpty) {
      _base44AccessToken = fromStorage;
    }
    return fromStorage;
  }
}
