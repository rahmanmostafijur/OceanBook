import 'package:flutter/material.dart';

/// The one loading indicator for page-level and list-level waits. The indicator is wrapped in a live
/// region with a localized [semanticLabel], so assistive tech announces that content is loading
/// (a bare progress indicator is silent). Pass the localized "loading" string or a more specific one.
class PageLoading extends StatelessWidget {
  /// A centered circular indicator, filling the space it is given.
  const PageLoading({required this.semanticLabel, super.key}) : linear = false;

  /// A thin linear indicator for in-place refreshes (it does not center itself).
  const PageLoading.linear({required this.semanticLabel, super.key}) : linear = true;

  final String semanticLabel;
  final bool linear;

  @override
  Widget build(BuildContext context) {
    final indicator = ExcludeSemantics(
      child: linear ? const LinearProgressIndicator() : const CircularProgressIndicator(),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticLabel,
      child: linear ? indicator : Center(child: indicator),
    );
  }
}
