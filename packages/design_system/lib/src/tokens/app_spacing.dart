import 'package:flutter/widgets.dart';

/// Spacing scale (dp). Larger gaps between sections, smaller inside related components.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;
  static const double giant = 64;

  /// Horizontal page gutter by window class (compact phones 16, everything wider 24).
  static double gutter(double width) => width < 600 ? md : xl;

  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets listTilePadding = EdgeInsets.symmetric(horizontal: md);
  static const double sectionGap = xxl;
}

/// Sizes that are not spacing: icons, touch targets, readable widths.
abstract final class AppSizes {
  static const double iconSmall = 18;
  static const double icon = 24;
  static const double iconLarge = 32;
  static const double iconHero = 48;

  /// Minimum interactive size (Material and WCAG 2.2 target size).
  static const double minTouchTarget = 48;

  /// Comfortable reading measure for long text and forms on large screens.
  static const double maxReadableWidth = 720;
  static const double maxFormWidth = 440;

  /// Book covers keep a 2:3 aspect ratio everywhere, so layout never shifts while images load.
  static const double coverAspectRatio = 2 / 3;
}
