import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:doublecheck_repairs/bridge/google_auth_bridge.dart';
import 'package:doublecheck_repairs/bridge/webview_bridge.dart';
import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:doublecheck_repairs/widgets/error_state_view.dart';
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

class _WebViewScreenState extends State<WebViewScreen> {
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
  bool _isGoogleAuthInProgress = false;

  @override
  void initState() {
    super.initState();
    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(color: AppConfig.brandColor),
      onRefresh: _handleRefresh,
    );
    _splashTimeout = Timer(const Duration(seconds: 12), _finishInitialLoad);
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    unawaited(_checkConnectivity());
  }

  @override
  void dispose() {
    _splashTimeout?.cancel();
    _navigationTimeout?.cancel();
    _connectivitySubscription?.cancel();
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
      !_showSplash &&
      !_showBlockingError &&
      (_isNavigating || _isGoogleAuthInProgress) &&
      _hasLoadedOnce;

  Future<void> _onWebViewCreated(InAppWebViewController controller) async {
    _webViewController = controller;
    await WebViewBridge.registerHandlers(
      controller,
      onUserInteraction: _onUserInteraction,
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
    await WebViewBridge.injectInteractionScript(controller);
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

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    if (!navigationAction.isForMainFrame) {
      return NavigationActionPolicy.ALLOW;
    }

    final url = navigationAction.request.url;
    if (url == null) return NavigationActionPolicy.ALLOW;

    final policy = await GoogleAuthBridge.interceptNavigation(
      url: url,
      webViewController: controller,
      onAuthStarted: () {
        if (!mounted) return;
        setState(() => _isGoogleAuthInProgress = true);
        _beginNavigation(indeterminate: true);
      },
      onAuthFinished: () {
        if (!mounted) return;
        setState(() => _isGoogleAuthInProgress = false);
        _endNavigation();
      },
    );

    return policy ?? NavigationActionPolicy.ALLOW;
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
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: _buildBody(),
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
            shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
            onReceivedError: _onReceivedError,
            onReceivedHttpError: _onReceivedHttpError,
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
      ],
    );
  }
}
