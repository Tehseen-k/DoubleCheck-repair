import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

enum ErrorStateType { offline, loadFailed }

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.type,
    required this.onRetry,
    this.message,
  });

  final ErrorStateType type;
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final isOffline = type == ErrorStateType.offline;

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                  size: 64,
                  color: AppConfig.brandColor,
                ),
                const SizedBox(height: 24),
                Text(
                  isOffline ? 'No internet connection' : 'Unable to load page',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  message ??
                      (isOffline
                          ? 'Check your connection and try again.'
                          : 'Something went wrong while loading the page.'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConfig.brandColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
