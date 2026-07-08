import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

class PlanSelectionSheet extends StatelessWidget {
  const PlanSelectionSheet({
    super.key,
    required this.onSelect,
    this.onRestore,
    this.isRestoring = false,
  });

  final void Function(String productId) onSelect;
  final VoidCallback? onRestore;
  final bool isRestoring;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Choose your plan',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Subscribe securely through Google Play. '
            'Cancel anytime from your Play Store account.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black54,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 24),
          _PlanOptionButton(
            title: 'Monthly',
            subtitle: '\$10 CAD / month',
            badge: null,
            onPressed: () => onSelect('monthly_10'),
          ),
          const SizedBox(height: 12),
          _PlanOptionButton(
            title: 'Yearly',
            subtitle: '\$99 CAD / year',
            badge: 'Best value',
            onPressed: () => onSelect('yearly_99'),
          ),
          if (onRestore != null) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: isRestoring ? null : onRestore,
              icon: isRestoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded, size: 20),
              label: Text(
                isRestoring ? 'Restoring…' : 'Restore previous purchase',
              ),
            ),
          ],
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
    this.badge,
  });

  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppConfig.brandColor.withValues(alpha: 0.5),
            ),
            color: AppConfig.brandColor.withValues(alpha: 0.04),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppConfig.brandColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppConfig.brandColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppConfig.brandColor,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
