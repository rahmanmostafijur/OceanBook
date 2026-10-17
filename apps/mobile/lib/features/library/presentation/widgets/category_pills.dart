import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// Horizontally scrollable genre selector. `null` is the leading "All" pill. Each pill is a
/// [ChoiceChip], so selection is announced and the 48 dp touch target is kept.
class CategoryPills extends StatelessWidget {
  const CategoryPills({required this.categories, required this.selected, required this.onSelected, super.key});

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final items = <String?>[null, ...categories];
    return Semantics(
      container: true,
      label: l10n.libraryCategoriesLabel,
      child: SizedBox(
        height: AppSizes.minTouchTarget,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            final category = items[index];
            return Center(
              child: ChoiceChip(
                label: Text(category ?? l10n.libraryCategoryAll),
                selected: category == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(category),
              ),
            );
          },
        ),
      ),
    );
  }
}
