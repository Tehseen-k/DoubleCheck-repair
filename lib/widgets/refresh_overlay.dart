import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

class PageLoadingOverlay extends StatelessWidget {
  const PageLoadingOverlay({
    super.key,
    this.message = 'Loading…',
    this.showSpinner = true,
  });

  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.white,
        child: showSpinner
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppConfig.brandColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppConfig.brandColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF374151),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// @deprecated Use [PageLoadingOverlay] with message: 'Refreshing…'
typedef RefreshOverlay = PageLoadingOverlay;
