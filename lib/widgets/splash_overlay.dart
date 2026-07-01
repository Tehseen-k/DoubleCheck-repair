import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';

class SplashOverlay extends StatelessWidget {
  const SplashOverlay({
    super.key,
    this.progress,
  });

  final double? progress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppConfig.brandColor,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Image(
                image: AssetImage('assets/images/app_icon.png'),
                width: 160,
                height: 160,
              ),
              const SizedBox(height: 40),
              Text(
                AppConfig.appName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
              ),
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: progress != null
                    ? LinearProgressIndicator(
                        value: progress!.clamp(0.05, 1.0),
                        minHeight: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      )
                    : const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
