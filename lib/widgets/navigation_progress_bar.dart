import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

class NavigationProgressBar extends StatelessWidget {
  const NavigationProgressBar({
    super.key,
    required this.progress,
    this.indeterminate = false,
    this.topInset = 0,
  });

  final double progress;
  final bool indeterminate;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppConfig.brandColor.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: indeterminate
            ? const LinearProgressIndicator(
                minHeight: 4,
                color: AppConfig.brandColor,
                backgroundColor: Color(0xFFFFE8B0),
              )
            : TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: progress.clamp(0.05, 1.0),
                ),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: AppConfig.brandColor,
                    backgroundColor: const Color(0xFFFFE8B0),
                  );
                },
              ),
      ),
    );
  }
}
