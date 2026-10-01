import 'package:flutter/widgets.dart';

/// Material 3 window size classes. Layouts adapt by class, never by device model.
enum WindowSize {
  compact, // < 600: phones (360-412 dp)
  medium, // 600-839: large phones in landscape, small tablets, foldables
  expanded, // 840-1199: tablets (768 portrait is medium, 1024 is expanded)
  large, // 1200-1599
  extraLarge; // >= 1600

  static WindowSize fromWidth(double width) {
    if (width < AppBreakpoints.medium) return WindowSize.compact;
    if (width < AppBreakpoints.expanded) return WindowSize.medium;
    if (width < AppBreakpoints.large) return WindowSize.expanded;
    if (width < AppBreakpoints.extraLarge) return WindowSize.large;
    return WindowSize.extraLarge;
  }

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == WindowSize.compact;
  bool operator >=(WindowSize other) => index >= other.index;
}

abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
  static const double large = 1200;
  static const double extraLarge = 1600;
}
