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
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppConfig.brandColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOffline
                        ? Icons.wifi_off_rounded
                        : Icons.cloud_off_rounded,
                    size: 44,
                    color: AppConfig.brandColor,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  isOffline ? 'You\'re offline' : 'Page couldn\'t load',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  message ??
                      (isOffline
                          ? 'Check your internet connection and try again.'
                          : 'Something went wrong while loading. Pull down to refresh or tap Retry.'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 36),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppConfig.brandColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
