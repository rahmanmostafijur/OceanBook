import 'package:flutter/widgets.dart';

/// Material 3 motion tokens. Motion communicates state, never decorates.
abstract final class AppMotion {
  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);
  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium4 = Duration(milliseconds: 400);
  static const Duration long2 = Duration(milliseconds: 500);

  static const Curve standard = Cubic(0.2, 0, 0, 1);
  static const Curve standardDecelerate = Cubic(0, 0, 0, 1);
  static const Curve standardAccelerate = Cubic(0.3, 0, 1, 1);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0, 0.8, 0.15);

  /// True when the platform asks for reduced motion; transitions should collapse to fades or nothing.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when the user prefers reduced motion.
  static Duration of(BuildContext context, Duration duration) => reduced(context) ? Duration.zero : duration;
}
