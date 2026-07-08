import 'package:flutter/material.dart';

enum AppSnackbarType { info, success, error }

abstract final class AppSnackbar {
  static void show(
    ScaffoldMessengerState messenger,
    String message, {
    AppSnackbarType type = AppSnackbarType.info,
    Duration duration = const Duration(seconds: 4),
  }) {
    final (icon, background) = switch (type) {
      AppSnackbarType.success => (
          Icons.check_circle_rounded,
          const Color(0xFF15803D),
        ),
      AppSnackbarType.error => (
          Icons.error_outline_rounded,
          const Color(0xFFB91C1C),
        ),
      AppSnackbarType.info => (
          Icons.info_outline_rounded,
          const Color(0xFF1F2937),
        ),
    };

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: duration,
        action: type == AppSnackbarType.error
            ? SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white70,
                onPressed: messenger.hideCurrentSnackBar,
              )
            : null,
      ),
    );
  }

  static void showSuccess(ScaffoldMessengerState messenger, String message) {
    show(messenger, message, type: AppSnackbarType.success);
  }

  static void showError(ScaffoldMessengerState messenger, String message) {
    show(messenger, message, type: AppSnackbarType.error);
  }

  static void showInfo(ScaffoldMessengerState messenger, String message) {
    show(messenger, message, type: AppSnackbarType.info);
  }
}
