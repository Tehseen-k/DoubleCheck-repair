import 'package:flutter/material.dart';

/// Central configuration for the DoubleCheck Repairs app.
abstract final class AppConfig {
  static const String appName = 'DoubleCheck Repairs';
  static const String webUrl = 'https://mechanic-ai-2b194910.base44.app';
  static const String allowedDomain = 'transparent.repairs.com';

  /// Base44 app ID for this deployment.
  static const String base44AppId = '6935e0781d8573e32b194910';

  /// Google OAuth redirect URI registered with Base44 / Google.
  static const String base44OAuthCallbackPath = '/api/apps/auth/callback';

  static const Color brandColor = Color(0xFFF59E0B);

  static const String oauthCallbackScheme = 'doublecheckrepairs';
  static const String oauthCallbackHost = 'auth-callback';

  static Uri get oauthCallbackUri => Uri(
        scheme: oauthCallbackScheme,
        host: oauthCallbackHost,
      );

  static Uri get webUri => Uri.parse(webUrl);

  static String get appHost => webUri.host;

  static Uri loginUri({required String fromUrl}) => webUri.replace(
        path: '/login',
        queryParameters: {'from_url': fromUrl},
      );
}
