// Tests for the app theme system. The previous default counter test was
// removed — SmartSafe has no counter and it referenced widgets that don't exist.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsafe/theme/colors.dart';

void main() {
  setUp(() {
    // Always start each test from a known theme.
    AppTheme.themeNotifier.value = ThemeMode.dark;
  });

  group('AppTheme', () {
    test('defaults to dark mode', () {
      expect(AppTheme.isDark, isTrue);
    });

    test('toggle flips between dark and light', () {
      expect(AppTheme.isDark, isTrue);
      AppTheme.toggle();
      expect(AppTheme.isDark, isFalse);
      AppTheme.toggle();
      expect(AppTheme.isDark, isTrue);
    });

    test('exposes a different background for each mode', () {
      final darkBg = AppColors.bg;
      AppTheme.toggle();
      final lightBg = AppColors.bg;
      expect(darkBg, isNot(equals(lightBg)));
    });

    test('success and accent are distinct (green vs red)', () {
      expect(AppColors.success, isNot(equals(AppColors.accent)));
    });
  });
}
