import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

class PlanSelectionSheet extends StatelessWidget {
  const PlanSelectionSheet({
    super.key,
    required this.onSelect,
  });

  final void Function(String productId) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose a plan',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a subscription to continue with Google Play billing.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                ),
          ),
          const SizedBox(height: 24),
          _PlanOptionButton(
            title: 'Monthly',
            subtitle: '\$10 CAD / month',
            onPressed: () => onSelect('monthly_10'),
          ),
          const SizedBox(height: 12),
          _PlanOptionButton(
            title: 'Yearly',
            subtitle: '\$99 CAD / year',
            onPressed: () => onSelect('yearly_99'),
          ),
        ],
      ),
    );
  }
}

class _PlanOptionButton extends StatelessWidget {
  const _PlanOptionButton({
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        side: const BorderSide(color: AppConfig.brandColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppConfig.brandColor),
        ],
      ),
    );
  }
}
