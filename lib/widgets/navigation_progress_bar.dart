import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

class NavigationProgressBar extends StatelessWidget {
  const NavigationProgressBar({
    super.key,
    required this.progress,
    this.indeterminate = false,
  });

  final double progress;
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      child: indeterminate
          ? const LinearProgressIndicator(
              minHeight: 3,
              color: AppConfig.brandColor,
              backgroundColor: Color(0xFFFFE8B0),
            )
          : LinearProgressIndicator(
              value: progress.clamp(0.05, 1.0),
              minHeight: 3,
              color: AppConfig.brandColor,
              backgroundColor: const Color(0xFFFFE8B0),
            ),
    );
  }
}
