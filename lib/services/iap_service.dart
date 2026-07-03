import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doublecheck_repairs/bridge/webview_session_bridge.dart';
import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

typedef IapSnackbarCallback = void Function(String message);
typedef IapSuccessCallback = void Function();

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

  bool _purchasePending = false;
  bool _initialized = false;

  bool get purchasePending => _purchasePending;
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
    if (!Platform.isAndroid) return;

    final product = _products[productId];
    if (product == null) {
      _showSnackbar('Product not available. Please try again later.');
      return;
    }

    debugPrint('IAP: initiating purchase for $productId');
    final purchaseParam = GooglePlayPurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    if (!Platform.isAndroid) return;
    debugPrint('IAP: restoring purchases');
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          debugPrint('IAP: purchase pending ${purchase.productID}');
          _setPurchasePending(true);

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          unawaited(_handleSuccessfulPurchase(purchase));

        case PurchaseStatus.error:
          debugPrint(
            'IAP: purchase error ${purchase.error?.code} '
            '${purchase.error?.message}',
          );
          unawaited(_completePurchaseIfNeeded(purchase));
          _setPurchasePending(false);
          _showSnackbar('Purchase failed. Please try again.');

        case PurchaseStatus.canceled:
          debugPrint('IAP: purchase canceled');
          _setPurchasePending(false);
      }
    }
  }

  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    final purchaseKey = purchase.purchaseID ?? purchase.productID;
    if (_processingPurchaseIds.contains(purchaseKey)) return;
    _processingPurchaseIds.add(purchaseKey);

    final token = purchase.verificationData.serverVerificationData;
    final tokenPreview =
        token.length > 20 ? token.substring(0, 20) : token;
    debugPrint(
      'IAP: purchase successful ${purchase.productID} token=$tokenPreview',
    );

    try {
      final verified = await verifyAndActivate(purchase);
      if (verified) {
        _onPurchaseSuccess?.call();
      }
    } finally {
      _processingPurchaseIds.remove(purchaseKey);
      _setPurchasePending(false);
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
        'Purchase recorded, please restart the app to '
        'activate your subscription',
      );
      return false;
    } on Exception catch (error) {
      debugPrint('IAP: backend verification error — $error');
      debugPrint(
        'IAP: backend verification failed — not completing purchase',
      );
      _showSnackbar(
        'Purchase recorded, please restart the app to '
        'activate your subscription',
      );
      return false;
    }
  }

  Future<void> _completePurchaseIfNeeded(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  void _setPurchasePending(bool pending) {
    if (_purchasePending == pending) return;
    _purchasePending = pending;
    notifyListeners();
  }

  void _showSnackbar(String message) {
    _onSnackbar?.call(message);
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
