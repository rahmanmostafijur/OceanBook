import 'package:flutter/material.dart';

/// Scrolls a [DataTable] vertically and, when the window is narrower than the table (or the text is
/// scaled up), horizontally too. At least as wide as its parent so a short table still fills it.
class ScrollableTable extends StatelessWidget {
  const ScrollableTable({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}
