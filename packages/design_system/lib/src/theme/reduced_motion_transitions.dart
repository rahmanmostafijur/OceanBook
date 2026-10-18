import 'package:flutter/material.dart';

/// Wraps a platform page transition and skips it when the user asks for reduced motion
/// (`MediaQuery.disableAnimationsOf`): the incoming page simply appears.
class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const ReducedMotionPageTransitionsBuilder(this.delegate);

  final PageTransitionsBuilder delegate;

  @override
  Duration get transitionDuration => delegate.transitionDuration;

  @override
  Duration get reverseTransitionDuration => delegate.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => delegate.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return delegate.buildTransitions<T>(route, context, animation, secondaryAnimation, child);
  }
}
