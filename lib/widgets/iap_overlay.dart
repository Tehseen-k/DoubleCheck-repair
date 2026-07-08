import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:doublecheck_repairs/services/iap_service.dart';
import 'package:flutter/material.dart';

class IapOverlay extends StatelessWidget {
  const IapOverlay({
    super.key,
    required this.state,
  });

  final IapUiState state;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = _contentForState(state);

    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppConfig.brandColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: AppConfig.brandColor, size: 28),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppConfig.brandColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, String, IconData) _contentForState(IapUiState state) {
    return switch (state) {
      IapUiState.restoring => (
          'Restoring purchases',
          'Checking Google Play for your previous subscriptions…',
          Icons.restore_rounded,
        ),
      IapUiState.verifying => (
          'Activating subscription',
          'Confirming your purchase with our servers. This may take a moment.',
          Icons.verified_user_outlined,
        ),
      IapUiState.awaitingStore => (
          'Waiting for Google Play',
          'Complete the purchase in the Google Play dialog.',
          Icons.shopping_bag_outlined,
        ),
      IapUiState.initiatingPurchase => (
          'Starting purchase',
          'Connecting to Google Play billing…',
          Icons.payment_rounded,
        ),
      IapUiState.idle => (
          'Processing',
          'Please wait…',
          Icons.hourglass_top_rounded,
        ),
    };
  }
}
