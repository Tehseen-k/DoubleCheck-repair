import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doublecheck_repairs/bridge/webview_session_bridge.dart';
import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

typedef IapSnackbarCallback = void Function(String message, {bool isError});
typedef IapSuccessCallback = void Function({required bool wasRestore});

enum IapUiState {
  idle,
  initiatingPurchase,
  awaitingStore,
  verifying,
  restoring,
}

/// Google Play subscription purchases and Base44 backend verification.
class IapService extends ChangeNotifier {
  IapService({
    IapSnackbarCallback? onSnackbar,
    IapSuccessCallback? onPurchaseSuccess,
  })  : _onSnackbar = onSnackbar,
        _onPurchaseSuccess = onPurchaseSuccess;

  final IapSnackbarCallback? _onSnackbar;
  final IapSuccessCallback? _onPurchaseSuccess;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final Map<String, ProductDetails> _products = {};
  final Set<String> _processingPurchaseIds = {};

  IapUiState _uiState = IapUiState.idle;
  bool _initialized = false;
  bool _isRestoreInProgress = false;
  Timer? _restoreTimeout;

  bool get purchasePending => _uiState != IapUiState.idle;
  IapUiState get uiState => _uiState;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('IAP: store not available');
      return;
    }

    _purchaseSubscription ??= _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (Object error) {
        debugPrint('IAP: purchase stream error — $error');
        _setUiState(IapUiState.idle);
        _showSnackbar(
          'Billing service error. Please try again later.',
          isError: true,
        );
      },
    );

    final response = await _iap.queryProductDetails(
      AppConfig.subscriptionProductIds.toSet(),
    );

    if (response.error != null) {
      debugPrint('IAP: queryProductDetails error — ${response.error}');
    }

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint(
        'IAP: WARNING products not found — check Play Console product IDs '
        'and that app is signed correctly. Missing: ${response.notFoundIDs}',
      );
    }

    _products
      ..clear()
      ..addEntries(
        response.productDetails.map((product) => MapEntry(product.id, product)),
      );

    debugPrint(
      'IAP: initialized, products loaded: ${response.productDetails.length}',
    );
    if (response.productDetails.isNotEmpty) {
      final details = response.productDetails
          .map((product) => '${product.id}=${product.price}')
          .join(', ');
      debugPrint('IAP: product details: $details');
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> purchaseSubscription(String productId) async {
    if (!Platform.isAndroid) {
      _showSnackbar('Purchases are only available on Android.', isError: true);
      return;
    }

    if (!_initialized) {
      _showSnackbar(
        'Billing is still loading. Please wait a moment and try again.',
        isError: true,
      );
      return;
    }

    final product = _products[productId];
    if (product == null) {
      _showSnackbar(
        'This plan is not available right now. Please try again later.',
        isError: true,
      );
      return;
    }

    debugPrint('IAP: initiating purchase for $productId');
    _setUiState(IapUiState.initiatingPurchase);

    try {
      final purchaseParam = GooglePlayPurchaseParam(productDetails: product);
      final started = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      if (!started) {
        _setUiState(IapUiState.idle);
        _showSnackbar(
          'Could not start the purchase. Please try again.',
          isError: true,
        );
      } else {
        _setUiState(IapUiState.awaitingStore);
      }
    } on Exception catch (error) {
      debugPrint('IAP: buyNonConsumable error — $error');
      _setUiState(IapUiState.idle);
      _showSnackbar(
        'Could not connect to Google Play. Please try again.',
        isError: true,
      );
    }
  }

  Future<void> restorePurchases() async {
    if (!Platform.isAndroid) {
      _showSnackbar('Restore is only available on Android.', isError: true);
      return;
    }

    if (!_initialized) {
      _showSnackbar(
        'Billing is still loading. Please wait a moment and try again.',
        isError: true,
      );
      return;
    }

    debugPrint('IAP: restoring purchases');
    _isRestoreInProgress = true;
    _setUiState(IapUiState.restoring);

    _restoreTimeout?.cancel();
    _restoreTimeout = Timer(const Duration(seconds: 12), () {
      if (!_isRestoreInProgress) return;
      _isRestoreInProgress = false;
      _setUiState(IapUiState.idle);
      _showSnackbar(
        'No previous subscriptions were found on this Google account.',
        isError: false,
      );
    });

    try {
      await _iap.restorePurchases();
    } on Exception catch (error) {
      debugPrint('IAP: restorePurchases error — $error');
      _restoreTimeout?.cancel();
      _isRestoreInProgress = false;
      _setUiState(IapUiState.idle);
      _showSnackbar(
        'Could not restore purchases. Please try again.',
        isError: true,
      );
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          debugPrint('IAP: purchase pending ${purchase.productID}');
          _setUiState(IapUiState.awaitingStore);

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _restoreTimeout?.cancel();
          _isRestoreInProgress = false;
          unawaited(_handleSuccessfulPurchase(purchase));

        case PurchaseStatus.error:
          debugPrint(
            'IAP: purchase error ${purchase.error?.code} '
            '${purchase.error?.message}',
          );
          unawaited(_completePurchaseIfNeeded(purchase));
          _restoreTimeout?.cancel();
          _isRestoreInProgress = false;
          _setUiState(IapUiState.idle);
          _showSnackbar(
            _friendlyPurchaseError(purchase.error),
            isError: true,
          );

        case PurchaseStatus.canceled:
          debugPrint('IAP: purchase canceled');
          _restoreTimeout?.cancel();
          _isRestoreInProgress = false;
          _setUiState(IapUiState.idle);
          _showSnackbar('Purchase cancelled.', isError: false);
      }
    }
  }

  String _friendlyPurchaseError(IAPError? error) {
    final code = error?.code ?? '';
    final message = error?.message ?? '';
    return switch (code) {
      'purchase_error' => 'Purchase failed. Please try again.',
      'store_unavailable' =>
        'Google Play is unavailable. Check your connection and try again.',
      'item_unavailable' =>
        'This subscription is not available in your region or account.',
      'user_canceled' => 'Purchase cancelled.',
      _ => message.isNotEmpty
          ? message
          : 'Purchase failed. Please try again.',
    };
  }

  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    final purchaseKey = purchase.purchaseID ?? purchase.productID;
    if (_processingPurchaseIds.contains(purchaseKey)) return;
    _processingPurchaseIds.add(purchaseKey);

    final wasRestore = purchase.status == PurchaseStatus.restored;
    final token = purchase.verificationData.serverVerificationData;
    final tokenPreview =
        token.length > 20 ? token.substring(0, 20) : token;
    debugPrint(
      'IAP: purchase successful ${purchase.productID} token=$tokenPreview',
    );

    _setUiState(IapUiState.verifying);

    try {
      final verified = await verifyAndActivate(purchase);
      if (verified) {
        _onPurchaseSuccess?.call(wasRestore: wasRestore);
      }
    } finally {
      _processingPurchaseIds.remove(purchaseKey);
      _setUiState(IapUiState.idle);
    }
  }

  Future<bool> verifyAndActivate(PurchaseDetails purchase) async {
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.verifyPurchaseUrl),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'platform': 'android',
              'productId': purchase.productID,
              'purchaseToken':
                  purchase.verificationData.serverVerificationData,
              'packageName': AppConfig.androidPackageName,
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'IAP: verifyPurchase status=${response.statusCode} body=${response.body}',
      );

      if (response.statusCode == 200) {
        debugPrint('IAP: backend verified — completing purchase');
        await _completePurchaseIfNeeded(purchase);
        await WebViewSessionBridge.notifySubscriptionUpdated();
        return true;
      }

      debugPrint(
        'IAP: backend verification failed — not completing purchase',
      );
      _showSnackbar(
        'Your purchase was received but activation failed. '
        'Please restart the app or contact support if the issue persists.',
        isError: true,
      );
      return false;
    } on Exception catch (error) {
      debugPrint('IAP: backend verification error — $error');
      _showSnackbar(
        'Could not verify your purchase. Check your connection and try again.',
        isError: true,
      );
      return false;
    }
  }

  Future<void> _completePurchaseIfNeeded(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  void _setUiState(IapUiState state) {
    if (_uiState == state) return;
    _uiState = state;
    notifyListeners();
  }

  void _showSnackbar(String message, {required bool isError}) {
    _onSnackbar?.call(message, isError: isError);
  }

  @override
  void dispose() {
    _restoreTimeout?.cancel();
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
