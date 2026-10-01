import 'package:flutter/material.dart';

/// Material 3 SearchBar exposed to assistive tech as one labelled text field. A bare SearchBar's tap
/// target carries no label (it fails the labelled-tap-target guideline), so every search uses this.
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({required this.hintText, this.onChanged, this.onSubmitted, this.fieldKey, super.key});

  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Key for the inner SearchBar (tests type into it).
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      label: hintText,
      textField: true,
      child: SearchBar(
        key: fieldKey,
        hintText: hintText,
        leading: const Icon(Icons.search),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    ),
  );
}
