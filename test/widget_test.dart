import 'package:doublecheck_repairs/config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App config has expected production values', () {
    expect(AppConfig.appName, 'DoubleCheck Repairs');
    expect(AppConfig.webUrl, 'https://mechanic-ai-2b194910.base44.app');
    expect(AppConfig.allowedDomain, 'transparent.repairs.com');
    expect(AppConfig.brandColor, const Color(0xFFF59E0B));
  });
}
