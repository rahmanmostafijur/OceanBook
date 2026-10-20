import 'package:flutter/material.dart';

/// Replaces the ink splash with a plain highlight when the user asks for reduced motion
/// (`MediaQuery.disableAnimationsOf`). The splash factory lives in [ThemeData], which cannot read
/// MediaQuery, so apps wrap their routes with this from `MaterialApp.builder`.
class ReducedMotionTheme extends StatelessWidget {
  const ReducedMotionTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return child;
    return Theme(
      data: Theme.of(context).copyWith(splashFactory: NoSplash.splashFactory),
      child: child,
    );
  }
}
