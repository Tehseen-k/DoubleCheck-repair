import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:doublecheck_repairs/bridge/webview_bridge.dart';
import 'package:doublecheck_repairs/bridge/webview_session_bridge.dart';
import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:doublecheck_repairs/services/google_auth_service.dart';
import 'package:doublecheck_repairs/services/iap_service.dart';
import 'package:doublecheck_repairs/widgets/error_state_view.dart';
import 'package:doublecheck_repairs/widgets/otp_registration_sheet.dart';
import 'package:doublecheck_repairs/widgets/plan_selection_sheet.dart';
import 'package:doublecheck_repairs/widgets/navigation_progress_bar.dart';
import 'package:doublecheck_repairs/widgets/splash_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  late final GoogleAuthService _authService;
  late final IapService _iapService;

  InAppWebViewController? _webViewController;
  PullToRefreshController? _pullToRefreshController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _splashTimeout;
  Timer? _navigationTimeout;

  bool _isOffline = false;
  bool _hasLoadError = false;
  String? _errorMessage;
  bool _hasLoadedOnce = false;
  bool _showSplash = true;
  bool _isNavigating = false;
  bool _navigationIndeterminate = false;
  double _loadProgress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService = GoogleAuthService(
      onSnackbar: (message) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
      onShowOtpSheet: _showOtpRegistrationSheet,
    );
    _iapService = IapService(
      onSnackbar: (message) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
      onPurchaseSuccess: () {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Subscription activated successfully!'),
          ),
        );
      },
    );
    _iapService.addListener(_onIapStateChanged);
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: AppConfig.brandColor),
      onRefresh: _handleRefresh,
    );
    _splashTimeout = Timer(const Duration(seconds: 12), _finishInitialLoad);
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    unawaited(_checkConnectivity());
    debugPrint('APP START: loading URL: ${AppConfig.webUrl}');
    debugPrint('APP START: calling signInSilently() in background');
    unawaited(_authService.initialize());
    unawaited(_iapService.initialize());
  }

  void _onIapStateChanged() {
    if (mounted) setState(() {});
  }

  void _onFlutterBridge(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    switch (type) {
      case 'purchase':
        final productId = message['productId']?.toString();
        _handleSubscriptionIntercept(productId);
      case 'select_plan':
        _showPlanSelectionSheet();
      case 'restore_purchases':
        debugPrint('BRIDGE: restore purchases requested');
        unawaited(_iapService.restorePurchases());
      default:
        debugPrint('BRIDGE: unknown message type: $type');
    }
  }

  void _handleSubscriptionIntercept(String? productId) {
    if (productId != null &&
        productId.isNotEmpty &&
        AppConfig.subscriptionProductIds.contains(productId)) {
      debugPrint('BRIDGE: intercepted Subscription POST — redirecting to IAP');
      debugPrint('BRIDGE: purchase request received for $productId');
      unawaited(_iapService.purchaseSubscription(productId));
      return;
    }

    debugPrint(
      'BRIDGE: intercepted Subscription POST — redirecting to IAP '
      '(plan selection required)',
    );
    _showPlanSelectionSheet();
  }

  String? _productIdFromSubscriptionUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('year')) return 'yearly_99';
    if (lower.contains('month')) return 'monthly_10';
    return null;
  }

  void _showPlanSelectionSheet() {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => PlanSelectionSheet(
        onSelect: (productId) {
          Navigator.of(context).pop();
          debugPrint('BRIDGE: purchase request received for $productId');
          unawaited(_iapService.purchaseSubscription(productId));
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_authService.onAppResumed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _splashTimeout?.cancel();
    _navigationTimeout?.cancel();
    _connectivitySubscription?.cancel();
    _iapService.removeListener(_onIapStateChanged);
    _iapService.dispose();
    WebViewSessionBridge.detach();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isOffline) {
      await _checkConnectivity(reloadOnSuccess: true);
      return;
    }
    _beginNavigation(indeterminate: true);
    await _webViewController?.reload();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final offline = _isConnectivityOffline(results);
    if (!offline || _isOffline || !mounted) return;
    setState(() {
      _isOffline = true;
      _hasLoadError = false;
      _showSplash = false;
      _isNavigating = false;
    });
    _endRefreshingSafely();
  }

  bool _isConnectivityOffline(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);
  }

  Future<void> _checkConnectivity({bool reloadOnSuccess = false}) async {
    final results = await Connectivity().checkConnectivity();
    final offline = _isConnectivityOffline(results);
    if (!mounted) return;

    setState(() {
      _isOffline = offline;
      if (offline) {
        _hasLoadError = false;
        _showSplash = false;
        _isNavigating = false;
        _errorMessage = null;
      } else if (reloadOnSuccess) {
        _hasLoadError = false;
        _errorMessage = null;
        if (!_hasLoadedOnce) {
          _showSplash = true;
        }
        _beginNavigation(indeterminate: true);
      }
    });

    if (offline) {
      _endRefreshingSafely();
      return;
    }

    if (reloadOnSuccess) {
      await _webViewController?.reload();
    }
  }

  Future<void> _retry() async {
    setState(() {
      _hasLoadError = false;
      _errorMessage = null;
      if (!_hasLoadedOnce) {
        _showSplash = true;
      }
    });
    _splashTimeout?.cancel();
    _splashTimeout = Timer(const Duration(seconds: 12), _finishInitialLoad);
    await _checkConnectivity(reloadOnSuccess: true);
  }

  void _endRefreshingSafely() {
    if (!mounted) return;
    try {
      _pullToRefreshController?.endRefreshing();
    } catch (_) {}
  }

  void _beginNavigation({bool indeterminate = false}) {
    _navigationTimeout?.cancel();
    setState(() {
      _isNavigating = true;
      _navigationIndeterminate = indeterminate;
      _loadProgress = 0.05;
    });
    _navigationTimeout = Timer(const Duration(seconds: 15), _endNavigation);
  }

  void _updateProgress(int progress) {
    if (!mounted || _hasLoadError) return;
    setState(() {
      _loadProgress = progress / 100.0;
      if (progress > 0 && progress < 100) {
        _isNavigating = true;
        _navigationIndeterminate = false;
      }
    });
    if (progress >= 100) {
      _finishInitialLoad();
    }
  }

  void _endNavigation() {
    if (!mounted) return;
    setState(() {
      _isNavigating = false;
      _navigationIndeterminate = false;
      _loadProgress = 0;
    });
  }

  void _finishInitialLoad() {
    _splashTimeout?.cancel();
    _navigationTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _showSplash = false;
      _isNavigating = false;
      _navigationIndeterminate = false;
      _loadProgress = 0;
      if (!_hasLoadError) {
        _hasLoadedOnce = true;
      }
    });
    _endRefreshingSafely();
  }

  bool get _showBlockingError =>
      _isOffline || (_hasLoadError && !_hasLoadedOnce);

  bool get _showLoadErrorOverlay => _hasLoadError && _hasLoadedOnce;

  bool get _showNavigationBar =>
      !_showSplash && !_showBlockingError && _isNavigating && _hasLoadedOnce;

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _webViewController = controller;
    WebViewSessionBridge.attach(controller);
    await WebViewBridge.injectFlutterAppFlag(controller);
    await WebViewBridge.registerHandlers(
      controller,
      onUserInteraction: _onUserInteraction,
      onFlutterBridge: _onFlutterBridge,
    );
  }

  void _onUserInteraction() {
    if (!_hasLoadedOnce || !mounted || _showSplash) return;
    _beginNavigation(indeterminate: true);
    _navigationTimeout?.cancel();
    _navigationTimeout =
        Timer(const Duration(seconds: 8), _endNavigation);
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    debugPrint('WEBVIEW LOAD START: url=$url');
    unawaited(WebViewBridge.injectPageLoadBridgeScripts(controller));
    if (!mounted) return;
    setState(() {
      _hasLoadError = false;
      _errorMessage = null;
      if (!_hasLoadedOnce) {
        _showSplash = true;
      }
    });
    _beginNavigation(indeterminate: !_hasLoadedOnce);
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    if (_hasLoadError) {
      _endRefreshingSafely();
      return;
    }
    unawaited(_reinjectInteractionScript(controller));
    _finishInitialLoad();
  }

  Future<void> _reinjectInteractionScript(
    InAppWebViewController controller,
  ) async {
    await WebViewBridge.injectPageLoadBridgeScripts(controller);
    await WebViewBridge.injectInteractionScript(controller);
    await WebViewBridge.logBridgeAvailability(controller);
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    _updateProgress(progress);
  }

  void _onUpdateVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    if (!_hasLoadedOnce || !mounted) return;
    setState(() {
      _isNavigating = true;
      _navigationIndeterminate = true;
    });
    _navigationTimeout?.cancel();
    _navigationTimeout =
        Timer(const Duration(milliseconds: 1500), _endNavigation);
  }

  void _onPageCommitVisible(InAppWebViewController controller, WebUri? url) {
    if (_hasLoadError || !_hasLoadedOnce) return;
    _finishInitialLoad();
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (!(request.isForMainFrame ?? false) || !mounted) return;
    _splashTimeout?.cancel();
    _navigationTimeout?.cancel();
    _endRefreshingSafely();
    setState(() {
      _showSplash = false;
      _isNavigating = false;
      _hasLoadError = true;
      _errorMessage = error.description;
    });
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  ) {
    if (!(request.isForMainFrame ?? false) || !mounted) return;
    final statusCode = errorResponse.statusCode ?? 0;
    if (statusCode < 400) return;

    _splashTimeout?.cancel();
    _navigationTimeout?.cancel();
    _endRefreshingSafely();
    setState(() {
      _showSplash = false;
      _isNavigating = false;
      _hasLoadError = true;
      _errorMessage = 'Server returned HTTP $statusCode.';
    });
  }

  Future<void> _handleBackNavigation() async {
    if (_webViewController != null && await _webViewController!.canGoBack()) {
      _beginNavigation(indeterminate: true);
      await _webViewController!.goBack();
      return;
    }
    await SystemNavigator.pop();
  }

  void _showOtpRegistrationSheet(OtpSheetRequest request) {
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => OtpRegistrationSheet(
        email: request.email,
        onVerify: request.onVerify,
        onResend: request.onResend,
        onDismiss: request.onDismiss,
      ),
    );
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url;
    final urlString = url?.toString() ?? '';
    final method =
        navigationAction.request.method?.toUpperCase() ?? 'GET';

    if (urlString.contains('entities/Subscription') && method == 'POST') {
      debugPrint('BRIDGE: intercepted Subscription POST — redirecting to IAP');
      _handleSubscriptionIntercept(_productIdFromSubscriptionUrl(urlString));
      return NavigationActionPolicy.CANCEL;
    }

    final isGoogleOAuth = GoogleAuthService.isGoogleOAuthUrl(url);
    final intercepted = isGoogleOAuth;

    debugPrint(
      'NAVIGATION: url=$urlString intercepted=$intercepted',
    );
    debugPrint(
      'GOOGLE INTERCEPT: detected=$isGoogleOAuth url=$urlString',
    );

    if (isGoogleOAuth) {
      debugPrint('NATIVE GOOGLE SIGNIN: triggered');
      unawaited(_authService.handleWebGoogleOAuthIntercept());
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  static final _webViewSettings = InAppWebViewSettings(
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    allowFileAccess: true,
    allowContentAccess: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    useOnLoadResource: true,
    useShouldOverrideUrlLoading: true,
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _showSplash
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: AppConfig.brandColor,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarColor: Colors.white,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleBackNavigation();
        },
        child: ScaffoldMessenger(
          key: _scaffoldMessengerKey,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: _buildBody(),
            ),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.black54),
                  onSelected: (value) {
                    if (value == 'restore') {
                      unawaited(_iapService.restorePurchases());
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'restore',
                      child: Text('Restore Purchases'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(AppConfig.webUrl)),
            initialSettings: _webViewSettings,
            pullToRefreshController: _pullToRefreshController,
            onWebViewCreated: _onWebViewCreated,
            onLoadStart: _onLoadStart,
            onLoadStop: _onLoadStop,
            onProgressChanged: _onProgressChanged,
            onUpdateVisitedHistory: _onUpdateVisitedHistory,
            onPageCommitVisible: _onPageCommitVisible,
            onReceivedError: _onReceivedError,
            onReceivedHttpError: _onReceivedHttpError,
            shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
          ),
        ),
        if (_showSplash && !_showBlockingError)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _showSplash ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: SplashOverlay(
                progress: _loadProgress > 0 ? _loadProgress : null,
              ),
            ),
          ),
        if (_showNavigationBar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: NavigationProgressBar(
              progress: _loadProgress,
              indeterminate: _navigationIndeterminate,
            ),
          ),
        if (_showBlockingError)
          Positioned.fill(
            child: ErrorStateView(
              type:
                  _isOffline ? ErrorStateType.offline : ErrorStateType.loadFailed,
              message: _isOffline ? null : _errorMessage,
              onRetry: _retry,
            ),
          ),
        if (_showLoadErrorOverlay)
          Positioned.fill(
            child: ErrorStateView(
              type: ErrorStateType.loadFailed,
              message: _errorMessage,
              onRetry: _retry,
            ),
          ),
        if (_iapService.purchasePending)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppConfig.brandColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
