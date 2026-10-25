import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Horizontally scrollable single-choice filter. Each pill is a [ChoiceChip], so selection is announced
/// and the 48 dp touch target is kept; the row grows with the text scale.
class FilterPills<T> extends StatelessWidget {
  const FilterPills({
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.semanticLabel,
    super.key,
  });

  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: AppSizes.chipRowHeight(context),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            final (value, label) = items[index];
            return Center(
              child: ChoiceChip(
                label: Text(label),
                selected: value == selected,
                showCheckmark: true,
                onSelected: (_) => onSelected(value),
              ),
            );
          },
        ),
      ),
    );
  }
}
