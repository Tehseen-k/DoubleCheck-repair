import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

typedef InteractionCallback = void Function();
typedef FlutterBridgeCallback = void Function(Map<String, dynamic> message);

/// Native ↔ JavaScript bridging for WebView features.
abstract final class WebViewBridge {
  static const String interactionHandler = 'interactionLoading';
  static const String flutterBridgeHandler = 'FlutterBridge';

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
