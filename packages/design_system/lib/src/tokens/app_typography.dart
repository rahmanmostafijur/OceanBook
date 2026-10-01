import 'package:flutter/material.dart';

/// Material 3 type scale with a Bangla + Latin font stack.
///
/// - UI: Noto Sans (Latin) with Noto Sans Bengali as fallback: harmonised metrics, full conjunct shaping.
/// - Reading (Phase 4): Noto Serif Bengali.
/// Fonts are bundled (no runtime download), so text renders the same offline.
/// Bangla needs more vertical room than Latin, so line heights are raised here, never per widget.
abstract final class AppTypography {
  static const String uiFamily = 'NotoSans';
  static const String bengaliFamily = 'NotoSansBengali';
  static const String readingBengaliFamily = 'NotoSerifBengali';
  static const String _package = 'design_system';
  static const List<String> fallback = ['packages/$_package/$bengaliFamily'];

  static TextTheme textTheme(ColorScheme scheme) {
    final base = Typography.material2021(platform: TargetPlatform.android, colorScheme: scheme).englishLike;
    TextStyle? style(
      TextStyle? s, {
      required double size,
      required double height,
      required FontWeight weight,
      double letterSpacing = 0,
    }) {
      return s?.copyWith(
        fontFamily: 'packages/$_package/$uiFamily',
        fontFamilyFallback: fallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        fontVariations: [FontVariation('wght', weight.value.toDouble())], // variable fonts
        letterSpacing: letterSpacing,
        color: scheme.onSurface,
      );
    }

    return TextTheme(
      displayLarge: style(base.displayLarge, size: 57, height: 1.16, weight: FontWeight.w400, letterSpacing: -0.25),
      displayMedium: style(base.displayMedium, size: 45, height: 1.18, weight: FontWeight.w400),
      displaySmall: style(base.displaySmall, size: 36, height: 1.24, weight: FontWeight.w400),
      headlineLarge: style(base.headlineLarge, size: 32, height: 1.3, weight: FontWeight.w500),
      headlineMedium: style(base.headlineMedium, size: 28, height: 1.32, weight: FontWeight.w500),
      headlineSmall: style(base.headlineSmall, size: 24, height: 1.36, weight: FontWeight.w500),
      titleLarge: style(base.titleLarge, size: 22, height: 1.4, weight: FontWeight.w500),
      titleMedium: style(base.titleMedium, size: 16, height: 1.5, weight: FontWeight.w600, letterSpacing: 0.15),
      titleSmall: style(base.titleSmall, size: 14, height: 1.45, weight: FontWeight.w600, letterSpacing: 0.1),
      bodyLarge: style(base.bodyLarge, size: 16, height: 1.6, weight: FontWeight.w400, letterSpacing: 0.15),
      bodyMedium: style(base.bodyMedium, size: 14, height: 1.55, weight: FontWeight.w400, letterSpacing: 0.25),
      bodySmall: style(base.bodySmall, size: 12, height: 1.5, weight: FontWeight.w400, letterSpacing: 0.4),
      labelLarge: style(base.labelLarge, size: 14, height: 1.45, weight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: style(base.labelMedium, size: 12, height: 1.4, weight: FontWeight.w600, letterSpacing: 0.5),
      labelSmall: style(base.labelSmall, size: 11, height: 1.4, weight: FontWeight.w600, letterSpacing: 0.5),
    );
  }
}
