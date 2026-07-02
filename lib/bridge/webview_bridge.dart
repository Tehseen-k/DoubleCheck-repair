import 'package:flutter_inappwebview/flutter_inappwebview.dart';

typedef InteractionCallback = void Function();

/// Native ↔ JavaScript bridging for WebView features.
abstract final class WebViewBridge {
  static const String interactionHandler = 'interactionLoading';

  static Future<void> registerHandlers(
    InAppWebViewController controller, {
    required InteractionCallback onUserInteraction,
  }) async {
    controller.addJavaScriptHandler(
      handlerName: interactionHandler,
      callback: (args) => onUserInteraction(),
    );
    await injectInteractionScript(controller);
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
