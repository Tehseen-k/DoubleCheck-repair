import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

typedef InteractionCallback = void Function();
typedef FlutterBridgeCallback = void Function(Map<String, dynamic> message);

/// Native ↔ JavaScript bridging for WebView features.
abstract final class WebViewBridge {
  static const String interactionHandler = 'interactionLoading';
  static const String flutterBridgeHandler = 'FlutterBridge';

  static const String _flutterAppStylesScript = r'''
(function () {
  if (window.__dcFlutterStylesInstalled) return;
  window.__dcFlutterStylesInstalled = true;

  window.isFlutterApp = true;
  window.FLUTTER_APP = true;
  document.documentElement.classList.add('dc-flutter-app');

  const style = document.createElement('style');
  style.id = 'dc-flutter-app-styles';
  style.textContent = `
    html.dc-flutter-app body {
      padding-top: env(safe-area-inset-top, 0px) !important;
      padding-bottom: env(safe-area-inset-bottom, 0px) !important;
    }
    html.dc-flutter-app header,
    html.dc-flutter-app nav,
    html.dc-flutter-app [class*="header"],
    html.dc-flutter-app [class*="navbar"],
    html.dc-flutter-app [class*="Navbar"] {
      padding-top: max(env(safe-area-inset-top, 0px), 8px) !important;
    }
    html.dc-flutter-app header .text-white,
    html.dc-flutter-app nav .text-white,
    html.dc-flutter-app [class*="header"] .text-white,
    html.dc-flutter-app [class*="navbar"] .text-white,
    html.dc-flutter-app header a,
    html.dc-flutter-app header button,
    html.dc-flutter-app nav a,
    html.dc-flutter-app nav button,
    html.dc-flutter-app [class*="header"] a,
    html.dc-flutter-app [class*="header"] button,
    html.dc-flutter-app [class*="navbar"] a,
    html.dc-flutter-app [class*="navbar"] button {
      color: #1F2937 !important;
      -webkit-text-fill-color: #1F2937 !important;
      opacity: 1 !important;
      visibility: visible !important;
    }
    html.dc-flutter-app a[href*="login"],
    html.dc-flutter-app a[href*="sign-in"],
    html.dc-flutter-app a[href*="signin"],
    html.dc-flutter-app .dc-auth-control {
      color: #B45309 !important;
      -webkit-text-fill-color: #B45309 !important;
      background-color: #FFFFFF !important;
      border: 1.5px solid #F59E0B !important;
      border-radius: 8px !important;
      box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1) !important;
      padding: 8px 16px !important;
      opacity: 1 !important;
      visibility: visible !important;
    }
  `;
  (document.head || document.documentElement).appendChild(style);

  const AUTH_TEXT = /sign\s*in|log\s*in|login|signin/i;

  function applyAuthStyles(el) {
    if (!el || el.dataset.dcAuthFixed === '1') return;
    el.dataset.dcAuthFixed = '1';
    el.classList.add('dc-auth-control');
    el.style.setProperty('color', '#B45309', 'important');
    el.style.setProperty('-webkit-text-fill-color', '#B45309', 'important');
    el.style.setProperty('background-color', '#FFFFFF', 'important');
    el.style.setProperty('border', '1.5px solid #F59E0B', 'important');
    el.style.setProperty('border-radius', '8px', 'important');
    el.style.setProperty('box-shadow', '0 1px 4px rgba(0,0,0,0.1)', 'important');
    el.style.setProperty('padding', '8px 16px', 'important');
    el.style.setProperty('opacity', '1', 'important');
    el.style.setProperty('visibility', 'visible', 'important');
    el.style.setProperty('display', 'inline-flex', 'important');
    el.style.setProperty('align-items', 'center', 'important');
    el.style.setProperty('justify-content', 'center', 'important');
  }

  function applyHeaderStyles(el) {
    if (!el || el.dataset.dcHeaderFixed === '1') return;
    el.dataset.dcHeaderFixed = '1';
    el.style.setProperty('color', '#1F2937', 'important');
    el.style.setProperty('-webkit-text-fill-color', '#1F2937', 'important');
    el.style.setProperty('opacity', '1', 'important');
    el.style.setProperty('visibility', 'visible', 'important');
  }

  function isAuthElement(el) {
    const text = (el.textContent || '').trim();
    const href = (el.getAttribute('href') || '').toLowerCase();
    const label = (el.getAttribute('aria-label') || '').trim();
    return AUTH_TEXT.test(text) ||
      AUTH_TEXT.test(label) ||
      href.includes('login') ||
      href.includes('signin') ||
      href.includes('sign-in');
  }

  function isHeaderElement(el) {
    return !!el.closest('header, nav, [class*="header"], [class*="navbar"], [class*="Navbar"]');
  }

  function scanAuthControls() {
    document.querySelectorAll('a, button, [role="button"]').forEach((el) => {
      if (isAuthElement(el)) {
        applyAuthStyles(el);
        return;
      }
      if (isHeaderElement(el)) {
        applyHeaderStyles(el);
      }
    });
  }

  scanAuthControls();

  let scans = 0;
  const interval = setInterval(() => {
    scanAuthControls();
    scans += 1;
    if (scans >= 20) clearInterval(interval);
  }, 500);

  const observer = new MutationObserver(() => {
    scanAuthControls();
  });
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['class', 'style', 'href'],
  });

  window.addEventListener('load', scanAuthControls);
  window.addEventListener('popstate', scanAuthControls);
})();
''';

  static UnmodifiableListView<UserScript> get initialUserScripts =>
      UnmodifiableListView<UserScript>([
        UserScript(
          source: _flutterAppStylesScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: true,
        ),
      ]);

  static Future<void> injectFlutterAppStyles(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(source: _flutterAppStylesScript);
    debugPrint('BRIDGE: injected Flutter app UI styles');
  }

  /// Registers [FlutterBridge] immediately — must run in [onWebViewCreated]
  /// before the web page can call `flutter_inappwebview.callHandler`.
  static void registerFlutterBridgeHandler(
    InAppWebViewController controller, {
    required FlutterBridgeCallback onFlutterBridge,
  }) {
    controller.addJavaScriptHandler(
      handlerName: flutterBridgeHandler,
      callback: (args) {
        final message = _parseBridgeMessage(args);
        if (message == null) {
          debugPrint('BRIDGE: FlutterBridge received unparseable args: $args');
          return;
        }
        debugPrint('BRIDGE: FlutterBridge message received: $message');
        onFlutterBridge(message);
      },
    );
    debugPrint('BRIDGE: FlutterBridge handler registered');
  }

  static Future<void> registerHandlers(
    InAppWebViewController controller, {
    required InteractionCallback onUserInteraction,
    required FlutterBridgeCallback onFlutterBridge,
  }) async {
    // Register FlutterBridge synchronously before any await so it is ready
    // as soon as the WebView is created.
    registerFlutterBridgeHandler(
      controller,
      onFlutterBridge: onFlutterBridge,
    );

    controller.addJavaScriptHandler(
      handlerName: interactionHandler,
      callback: (args) => onUserInteraction(),
    );

    await injectInteractionScript(controller);
  }

  static Map<String, dynamic>? _parseBridgeMessage(List<dynamic> args) {
    if (args.isEmpty) return null;

    final raw = args.first;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    if (raw is String) {
      return {'type': raw};
    }
    return null;
  }

  static Future<void> injectFlutterAppFlag(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(source: '''
      window.isFlutterApp = true;
      window.FLUTTER_APP = true;
    ''');
    debugPrint('BRIDGE: injected isFlutterApp flag into WebView');
  }

  /// Injects Flutter app flags and intercepts subscription POST fetch/XHR calls.
  static Future<void> injectPageLoadBridgeScripts(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(source: '''
      (function () {
        window.isFlutterApp = true;
        window.FLUTTER_APP = true;

        if (!window.__dcOriginalFetch) {
          window.__dcOriginalFetch = window.fetch.bind(window);
        }
        if (!window.__dcOriginalXhrOpen) {
          window.__dcOriginalXhrOpen = XMLHttpRequest.prototype.open;
        }
        if (!window.__dcOriginalXhrSend) {
          window.__dcOriginalXhrSend = XMLHttpRequest.prototype.send;
        }

        function getUrlString(url) {
          if (typeof url === 'string') return url;
          if (url && typeof url.url === 'string') return url.url;
          return '';
        }

        function isSubscriptionPost(url, method) {
          const urlStr = getUrlString(url);
          const methodStr = (method || 'GET').toUpperCase();
          return urlStr.includes('entities/Subscription') &&
            methodStr === 'POST';
        }

        function parseProductId(body) {
          if (!body) return null;
          try {
            const data = typeof body === 'string' ? JSON.parse(body) : body;
            const plan = String(
              data.plan || data.subscription_plan || data.billing_period || ''
            ).toLowerCase();
            if (plan.includes('year')) return 'yearly_99';
            if (plan.includes('month')) return 'monthly_10';
            const productId = data.productId || data.product_id;
            if (productId === 'yearly_99' || productId === 'monthly_10') {
              return productId;
            }
            return null;
          } catch (e) {
            return null;
          }
        }

        function redirectToIap(productId) {
          if (!window.flutter_inappwebview) return false;
          if (productId) {
            window.flutter_inappwebview.callHandler('FlutterBridge', {
              type: 'purchase',
              productId: productId,
            });
          } else {
            window.flutter_inappwebview.callHandler('FlutterBridge', {
              type: 'select_plan',
            });
          }
          return true;
        }

        function interceptSubscription(url, method, body) {
          if (!window.isFlutterApp || !isSubscriptionPost(url, method)) {
            return false;
          }
          const productId = parseProductId(body);
          return redirectToIap(productId);
        }

        const originalFetch = window.__dcOriginalFetch;
        window.fetch = function (url, options) {
          const opts = options || {};
          const method = opts.method || 'GET';
          if (interceptSubscription(url, method, opts.body)) {
            return new Promise(function () {});
          }
          return originalFetch.apply(this, arguments);
        };

        XMLHttpRequest.prototype.open = function (method, url) {
          this.__dcMethod = method;
          this.__dcUrl = url;
          return window.__dcOriginalXhrOpen.apply(this, arguments);
        };

        XMLHttpRequest.prototype.send = function (body) {
          if (interceptSubscription(this.__dcUrl, this.__dcMethod, body)) {
            return;
          }
          return window.__dcOriginalXhrSend.apply(this, arguments);
        };

        function detectPlanFromClick(target) {
          const button = target.closest(
            'button, a, [role="button"], [data-plan]'
          );
          if (!button) return null;

          const dataPlan = button.getAttribute('data-plan') ||
            button.closest('[data-plan]')?.getAttribute('data-plan');
          if (dataPlan) {
            const p = String(dataPlan).toLowerCase();
            if (p.includes('year')) return 'yearly';
            if (p.includes('month')) return 'monthly';
          }

          const container = button.closest('div, section, article, li') || button;
          const text = (container.textContent || '').toLowerCase();
          if (text.includes('yearly') || text.includes('/year') ||
              text.includes('99')) {
            return 'yearly';
          }
          if (text.includes('monthly') || text.includes('/month') ||
              text.includes('10')) {
            return 'monthly';
          }
          return null;
        }

        function isPricingPage() {
          const path = (window.location.pathname || '').toLowerCase();
          return path.includes('pricing') || path.includes('subscribe');
        }

        function isPlanButtonClick(target) {
          const button = target.closest('button, a, [role="button"]');
          if (!button || !isPricingPage()) return false;
          const text = (button.textContent || '').toLowerCase();
          return (
            text.includes('subscribe') ||
            text.includes('get started') ||
            text.includes('choose') ||
            text.includes('select') ||
            text.includes('start') ||
            button.closest('[data-plan]') != null ||
            detectPlanFromClick(target) != null
          );
        }

        // Base44 can call this at the top of their plan button handler.
        window.__dcHandlePlanButtonClick = function (plan) {
          console.log(
            'PLAN BUTTON CLICKED - isFlutterApp:',
            window.flutter_inappwebview !== undefined
          );
          if (window.flutter_inappwebview !== undefined) {
            window.flutter_inappwebview.callHandler('FlutterBridge', {
              type: 'purchase',
              productId: plan === 'yearly' ? 'yearly_99' : 'monthly_10',
            });
            return true;
          }
          return false;
        };

        if (!window.__dcPricingClickInstalled) {
          window.__dcPricingClickInstalled = true;
          document.addEventListener('click', function (event) {
            if (!isPlanButtonClick(event.target)) return;

            const plan = detectPlanFromClick(event.target);

            console.log(
              'PLAN BUTTON CLICKED - isFlutterApp:',
              window.flutter_inappwebview !== undefined
            );

            if (window.flutter_inappwebview !== undefined) {
              window.flutter_inappwebview.callHandler('FlutterBridge', {
                type: 'purchase',
                productId: plan === 'yearly' ? 'yearly_99' : 'monthly_10',
              });
              event.stopImmediatePropagation();
              event.preventDefault();
            }
          }, true);
        }
      })();
    ''');
    await injectFlutterAppStyles(controller);
    debugPrint('BRIDGE: injected isFlutterApp flag into WebView');
    debugPrint('BRIDGE: injected subscription fetch/XHR intercept');
    debugPrint('BRIDGE: injected pricing page plan click intercept');
  }

  static Future<void> logBridgeAvailability(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(source: '''
      (function () {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          console.log('FlutterBridge: flutter_inappwebview.callHandler is available');
        } else {
          console.warn('FlutterBridge: flutter_inappwebview.callHandler is NOT available');
        }
      })();
    ''');
  }

  static Future<void> injectInteractionScript(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(source: '''
      (function () {
        if (window.__dcInteractionHookInstalled) return;
        window.__dcInteractionHookInstalled = true;

        const notify = () => {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('$interactionHandler');
          }
        };

        document.addEventListener('click', (event) => {
          const target = event.target.closest(
            'a[href], button, [role="button"], input[type="submit"]'
          );
          if (target) notify();
        }, true);

        const wrapHistory = (method) => {
          const original = history[method];
          history[method] = function () {
            notify();
            return original.apply(this, arguments);
          };
        };
        wrapHistory('pushState');
        wrapHistory('replaceState');
        window.addEventListener('popstate', notify);
      })();
    ''');
  }
}
