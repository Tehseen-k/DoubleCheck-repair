import 'package:flutter/material.dart';

/// Central configuration for the DoubleCheck Repairs app.
abstract final class AppConfig {
  static const String appName = 'DoubleCheck Repairs';
  static const String webUrl = 'https://mechanic-ai-2b194910.base44.app';
  static const String dashboardUrl = 'https://mechanic-ai-2b194910.base44.app/dashboard';
  static const String loginUrl = 'https://mechanic-ai-2b194910.base44.app/login';
  static const String allowedDomain = 'transparent.repairs.com';

  static const String base44AppId = '6935e0781d8573e32b194910';
  static const String mobileGoogleLoginUrl =
      'https://mechanic-ai-2b194910.base44.app/api/functions/mobileGoogleLogin';
  static const String mobileRegisterUrl =
      'https://mechanic-ai-2b194910.base44.app/api/functions/mobileRegister';
  static const String verifyPurchaseUrl =
      'https://mechanic-ai-2b194910.base44.app/api/functions/verifyPurchase';

  static const String androidPackageName = 'com.transparentrepairs.app';
  static const List<String> subscriptionProductIds = [
    'monthly_10',
    'yearly_99',
  ];

  static const String sessionStorageKey = 'base44_access_token';
  static const String legacyTokenStorageKey = 'token';

  static const String googleWebClientId =
      '437384066136-puhse033ujiifvlbu8iiajmjva664i95.apps.googleusercontent.com';
  static const String googleAndroidClientId =
      '437384066136-3l660m8nra42me3fiqkbadljm1on8g9v.apps.googleusercontent.com';
  static const String googleIosClientId =
      '437384066136-5c7u708m1oc4uejc51qg94ngkutll42r.apps.googleusercontent.com';
  static const String googleIosReversedClientId =
      'com.googleusercontent.apps.437384066136-5c7u708m1oc4uejc51qg94ngkutll42r';

  static const Color brandColor = Color(0xFFF59E0B);
}
