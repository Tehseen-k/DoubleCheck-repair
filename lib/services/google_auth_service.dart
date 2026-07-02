import 'dart:convert';
import 'dart:io';

import 'package:doublecheck_repairs/bridge/webview_session_bridge.dart';
import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart' as custom_tabs;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

typedef AuthSnackbarCallback = void Function(String message);
typedef ShowOtpSheetCallback = void Function(OtpSheetRequest request);

enum OtpVerifyResult { success, invalidOtp, error }

class OtpSheetRequest {
  OtpSheetRequest({
    required this.email,
    required this.onVerify,
    required this.onResend,
    required this.onDismiss,
  });

  final String email;
  final Future<OtpVerifyResult> Function(String otp) onVerify;
  final Future<void> Function() onResend;
  final Future<void> Function() onDismiss;
}

sealed class MobileLoginResult {}

class MobileLoginSuccess extends MobileLoginResult {
  MobileLoginSuccess(this.accessToken);
  final String accessToken;
}

class MobileLoginNewUser extends MobileLoginResult {}

class MobileLoginExistingGoogleUserRequiresWebLogin extends MobileLoginResult {}

class MobileLoginInvalidToken extends MobileLoginResult {}

class MobileLoginServerError extends MobileLoginResult {}

sealed class RegisterStep1Result {}

class RegisterStep1OtpSent extends RegisterStep1Result {}

class RegisterStep1UserAlreadyExists extends RegisterStep1Result {}

class RegisterStep1Error extends RegisterStep1Result {}

sealed class RegisterStep2Result {}

class RegisterStep2Success extends RegisterStep2Result {
  RegisterStep2Success(this.accessToken);
  final String accessToken;
}

class RegisterStep2InvalidOtp extends RegisterStep2Result {}

class RegisterStep2Error extends RegisterStep2Result {}

/// Background Google Sign-In for silent login and WebView OAuth interception.
class GoogleAuthService {
  GoogleAuthService({
    AuthSnackbarCallback? onSnackbar,
    ShowOtpSheetCallback? onShowOtpSheet,
  })  : _onSnackbar = onSnackbar,
        _onShowOtpSheet = onShowOtpSheet,
        _googleSignIn = _createGoogleSignIn();

  final AuthSnackbarCallback? _onSnackbar;
  final ShowOtpSheetCallback? _onShowOtpSheet;
  final GoogleSignIn _googleSignIn;

  bool _signInInProgress = false;
  bool _pendingWebLoginReload = false;
  String? _pendingRegisterIdToken;

  static bool isGoogleOAuthUrl(WebUri? url) {
    if (url == null) return false;
    return url.host == 'accounts.google.com';
  }

  static GoogleSignIn _createGoogleSignIn() {
    return GoogleSignIn(
      scopes: const ['email', 'profile', 'openid'],
      serverClientId: AppConfig.googleWebClientId,
    );
  }

  /// Silent sign-in on app start — does nothing visible if it fails.
  Future<void> initialize() async {
    debugPrint('APP START: signInSilently() starting');
    await _trySilentSignIn();
    debugPrint('APP START: signInSilently() finished');
  }

  /// Called when the app returns to foreground after browser login flows.
  Future<void> onAppResumed() async {
    if (_pendingWebLoginReload) {
      _pendingWebLoginReload = false;
      debugPrint(
        'CUSTOM TAB: dismissed, reloading WebView at dashboard '
        '(existing_google_user flow — no mobileGoogleLogin retry)',
      );
      await WebViewSessionBridge.navigateTo(AppConfig.dashboardUrl);
    }
  }

  /// Triggered when the WebView intercepts a Google OAuth navigation.
  Future<void> handleWebGoogleOAuthIntercept() async {
    if (_signInInProgress) {
      debugPrint(
        'NATIVE GOOGLE SIGNIN: skipped — sign-in already in progress',
      );
      return;
    }
    _signInInProgress = true;

    try {
      debugPrint('NATIVE GOOGLE SIGNIN: calling google_sign_in.signIn()');
      final account = await _googleSignIn.signIn();
      if (account == null) {
        debugPrint('NATIVE SIGNIN: cancelled — no account returned');
        return;
      }

      final idToken = (await account.authentication).idToken;
      final idTokenPreview = idToken == null
          ? 'null'
          : idToken.length > 20
              ? idToken.substring(0, 20)
              : idToken;
      debugPrint(
        'NATIVE SIGNIN: account=${account.email} idToken=$idTokenPreview',
      );
      if (idToken == null) {
        _showSnackbar('Sign in failed, please try again');
        return;
      }

      await _handleMobileLoginResult(
        await _callMobileGoogleLogin(idToken),
        idToken: idToken,
        email: account.email,
      );
    } on PlatformException catch (error) {
      if (_isUserCancelled(error)) {
        debugPrint('NATIVE SIGNIN: cancelled by user');
        return;
      }
      debugPrint('NATIVE SIGNIN ERROR: ${error.code} — ${error.message}');
      _showSnackbar('Sign in failed, please try again');
    } catch (error, stackTrace) {
      debugPrint('NATIVE SIGNIN ERROR: $error');
      debugPrint('$stackTrace');
      _showSnackbar('Something went wrong, please try again');
    } finally {
      _signInInProgress = false;
    }
  }

  Future<void> _trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) {
        debugPrint(
          'APP START: signInSilently() returned null — '
          'WebView stays on current page',
        );
        return;
      }

      final idToken = (await account.authentication).idToken;
      final idTokenPreview = idToken == null
          ? 'null'
          : idToken.length > 20
              ? idToken.substring(0, 20)
              : idToken;
      debugPrint(
        'APP START: signInSilently() account=${account.email} '
        'idToken=$idTokenPreview',
      );
      if (idToken == null) {
        debugPrint(
          'APP START: signInSilently() idToken is null — no mobileGoogleLogin',
        );
        return;
      }

      debugPrint('APP START: calling mobileGoogleLogin after silent sign-in');
      await _handleMobileLoginResult(
        await _callMobileGoogleLogin(idToken),
        idToken: idToken,
        email: account.email,
      );
    } catch (error, stackTrace) {
      debugPrint('APP START: silent sign-in failed — $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _handleMobileLoginResult(
    MobileLoginResult result, {
    required String idToken,
    required String email,
  }) async {
    switch (result) {
      case MobileLoginSuccess(:final accessToken):
        debugPrint('MOBILE LOGIN: success — proceeding to session inject');
        await _completeAuthenticatedLogin(accessToken);
        _pendingWebLoginReload = false;
        _pendingRegisterIdToken = null;

      case MobileLoginNewUser():
        debugPrint('MOBILE LOGIN: new_user_requires_web_signup — mobileRegister');
        await _handleNewUserRegistration(idToken, email);

      case MobileLoginExistingGoogleUserRequiresWebLogin():
        debugPrint(
          'EXISTING GOOGLE USER: opening Custom Tab for web login',
        );
        await _openWebLoginForExistingUser();

      case MobileLoginInvalidToken():
        debugPrint('MOBILE LOGIN: invalid_token — signing out Google session');
        await _googleSignIn.signOut();
        _showSnackbar('Sign in failed, please try again');

      case MobileLoginServerError():
        debugPrint('MOBILE LOGIN: server error');
        _showSnackbar('Something went wrong, please try again');
    }
  }

  Future<void> _handleNewUserRegistration(String idToken, String email) async {
    debugPrint('REGISTER: calling mobileRegister step 1 email=$email');
    final step1 = await _callMobileRegisterStep1(idToken);

    switch (step1) {
      case RegisterStep1UserAlreadyExists():
        debugPrint(
          'REGISTER: user_already_exists — retrying mobileGoogleLogin',
        );
        final retry = await _callMobileGoogleLogin(idToken);
        if (retry is MobileLoginSuccess) {
          await _completeAuthenticatedLogin(retry.accessToken);
          return;
        }
        _showSnackbar('Please sign in with email and password instead');

      case RegisterStep1OtpSent():
        _pendingRegisterIdToken = idToken;
        debugPrint('REGISTER: otp_sent — showing OTP sheet');
        _onShowOtpSheet?.call(
          OtpSheetRequest(
            email: email,
            onVerify: _verifyRegistrationOtp,
            onResend: _resendRegistrationOtp,
            onDismiss: _dismissRegistration,
          ),
        );

      case RegisterStep1Error():
        _showSnackbar('Something went wrong, please try again');
    }
  }

  Future<OtpVerifyResult> _verifyRegistrationOtp(String otp) async {
    final idToken = _pendingRegisterIdToken;
    if (idToken == null) return OtpVerifyResult.error;

    debugPrint('REGISTER: calling mobileRegister step 2 with OTP');
    final result = await _callMobileRegisterStep2(idToken, otp);

    switch (result) {
      case RegisterStep2Success(:final accessToken):
        debugPrint('REGISTER: success — injecting session');
        _pendingRegisterIdToken = null;
        await _completeAuthenticatedLogin(accessToken);
        return OtpVerifyResult.success;

      case RegisterStep2InvalidOtp():
        debugPrint('REGISTER: invalid_otp — showing error in sheet');
        return OtpVerifyResult.invalidOtp;

      case RegisterStep2Error():
        return OtpVerifyResult.error;
    }
  }

  Future<void> _resendRegistrationOtp() async {
    final idToken = _pendingRegisterIdToken;
    if (idToken == null) return;

    final step1 = await _callMobileRegisterStep1(idToken);
    if (step1 is! RegisterStep1OtpSent) {
      _showSnackbar('Something went wrong, please try again');
    }
  }

  Future<void> _dismissRegistration() async {
    _pendingRegisterIdToken = null;
    await _googleSignIn.signOut();
    await WebViewSessionBridge.navigateTo(AppConfig.loginUrl);
  }

  Future<void> _completeAuthenticatedLogin(String accessToken) async {
    debugPrint(
      'MOBILE LOGIN: HTTP 200 — injecting session and navigating to dashboard',
    );
    await WebViewSessionBridge.injectAccessTokenAndNavigateToDashboard(
      accessToken,
    );
  }

  Future<void> _openWebLoginForExistingUser() async {
    debugPrint(
      'EXISTING GOOGLE USER: opening Custom Tab url=${AppConfig.loginUrl}',
    );
    _showSnackbar('Please complete sign in with Google in the browser');
    _pendingWebLoginReload = true;
    await _launchLoginInBrowser(
      onLaunchFailed: () => _pendingWebLoginReload = false,
    );
  }

  Future<void> _launchLoginInBrowser({
    required void Function() onLaunchFailed,
  }) async {
    final loginUri = Uri.parse(AppConfig.loginUrl);
    debugPrint('CUSTOM TAB: launching browser url=$loginUri');
    try {
      if (Platform.isAndroid) {
        await custom_tabs.launchUrl(
          loginUri,
          customTabsOptions: custom_tabs.CustomTabsOptions(
            colorSchemes: custom_tabs.CustomTabsColorSchemes.defaults(
              toolbarColor: AppConfig.brandColor,
            ),
            shareState: custom_tabs.CustomTabsShareState.on,
            urlBarHidingEnabled: true,
            showTitle: true,
          ),
        );
        debugPrint('CUSTOM TAB: opened successfully on Android');
      } else {
        final launched = await launchUrl(
          loginUri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          debugPrint('CUSTOM TAB: failed to launch browser on iOS');
          onLaunchFailed();
          _showSnackbar('Something went wrong, please try again');
        } else {
          debugPrint('CUSTOM TAB: opened successfully on iOS');
        }
      }
    } catch (error, stackTrace) {
      debugPrint('CUSTOM TAB ERROR: $error');
      debugPrint('$stackTrace');
      onLaunchFailed();
      _showSnackbar('Something went wrong, please try again');
    }
  }

  Future<MobileLoginResult> _callMobileGoogleLogin(String idToken) async {
    _logIdTokenDebug(idToken);

    try {
      debugPrint('MOBILE LOGIN: POST ${AppConfig.mobileGoogleLoginUrl}');

      final response = await http
          .post(
            Uri.parse(AppConfig.mobileGoogleLoginUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'MOBILE LOGIN: status=${response.statusCode} body=${response.body}',
      );

      return _parseMobileLoginResponse(response);
    } on http.ClientException {
      return MobileLoginServerError();
    } on Exception {
      return MobileLoginServerError();
    }
  }

  MobileLoginResult _parseMobileLoginResponse(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    } catch (_) {}

    final errorCode = _extractErrorCode(body, response.body);

    if (response.statusCode == 200) {
      final accessToken = body?['access_token'] as String?;
      if (accessToken != null && accessToken.isNotEmpty) {
        return MobileLoginSuccess(accessToken);
      }
      return MobileLoginServerError();
    }

    if (response.statusCode == 404 &&
        errorCode.contains('new_user_requires_web_signup')) {
      return MobileLoginNewUser();
    }

    if (response.statusCode == 403 &&
        errorCode.contains('existing_google_user_requires_web_login')) {
      debugPrint(
        'GoogleAuthService: mobileGoogleLogin returned '
        'existing_google_user_requires_web_login — opening web login',
      );
      return MobileLoginExistingGoogleUserRequiresWebLogin();
    }

    if (response.statusCode == 401 ||
        errorCode.contains('invalid_token') ||
        errorCode.contains('token_expired')) {
      return MobileLoginInvalidToken();
    }

    return MobileLoginServerError();
  }

  Future<RegisterStep1Result> _callMobileRegisterStep1(String idToken) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.mobileRegisterUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'REGISTER: step 1 status=${response.statusCode} body=${response.body}',
      );

      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (_) {}

      final errorCode = _extractErrorCode(body, response.body);

      if (response.statusCode == 200 &&
          body?['status']?.toString() == 'otp_sent') {
        return RegisterStep1OtpSent();
      }

      if (response.statusCode == 409 &&
          errorCode.contains('user_already_exists')) {
        return RegisterStep1UserAlreadyExists();
      }

      return RegisterStep1Error();
    } on http.ClientException {
      return RegisterStep1Error();
    } on Exception {
      return RegisterStep1Error();
    }
  }

  Future<RegisterStep2Result> _callMobileRegisterStep2(
    String idToken,
    String otp,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.mobileRegisterUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'id_token': idToken, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'REGISTER: step 2 status=${response.statusCode} body=${response.body}',
      );

      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (_) {}

      final errorCode = _extractErrorCode(body, response.body);

      if (response.statusCode == 200) {
        final accessToken = body?['access_token'] as String?;
        if (accessToken != null && accessToken.isNotEmpty) {
          return RegisterStep2Success(accessToken);
        }
        return RegisterStep2Error();
      }

      if (response.statusCode == 400 &&
          errorCode.contains('invalid_otp')) {
        return RegisterStep2InvalidOtp();
      }

      return RegisterStep2Error();
    } on http.ClientException {
      return RegisterStep2Error();
    } on Exception {
      return RegisterStep2Error();
    }
  }

  void _logIdTokenDebug(String idToken) {
    final preview =
        idToken.length > 50 ? idToken.substring(0, 50) : idToken;
    debugPrint(
      'GoogleAuthService: idToken preview (first 50 chars): $preview...',
    );

    try {
      final parts = idToken.split('.');
      if (parts.length >= 2) {
        final normalized = base64Url.normalize(parts[1]);
        final payloadJson = utf8.decode(base64Url.decode(normalized));
        final payload = jsonDecode(payloadJson);
        if (payload is Map<String, dynamic>) {
          debugPrint('GoogleAuthService: idToken aud: ${payload['aud']}');
        }
      }
    } catch (error) {
      debugPrint('GoogleAuthService: could not decode idToken payload: $error');
    }
  }

  String _extractErrorCode(Map<String, dynamic>? body, String rawBody) {
    final parts = <String?>[
      body?['error']?.toString(),
      body?['code']?.toString(),
      body?['message']?.toString(),
      body?['detail']?.toString(),
      rawBody,
    ];
    return parts.whereType<String>().join(' ').toLowerCase();
  }

  bool _isUserCancelled(PlatformException error) {
    return error.code == 'sign_in_canceled' ||
        error.code == 'CANCELED' ||
        error.code == 'cancelled';
  }

  void _showSnackbar(String message) {
    _onSnackbar?.call(message);
  }
}
