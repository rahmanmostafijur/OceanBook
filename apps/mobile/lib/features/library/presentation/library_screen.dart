import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../data/library_providers.dart';
import 'widgets/book_details_sheet.dart';
import 'widgets/category_pills.dart';
import 'widgets/library_book_card.dart';

const double _minTileWidth = 150;
const double _gridSpacing = AppSpacing.sm;

/// Library dashboard (signed-in only): sticky search, genre pills and a responsive cover grid.
/// Reading, downloads and sync arrive in Phase 4, so the shelf is sample data for now.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final books = ref.watch(visibleLibraryBooksProvider);
    final filter = ref.watch(libraryFilterProvider);
    final categories = ref.watch(libraryCategoriesProvider);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(title: Text(l10n.libraryTitle), pinned: false, floating: true, snap: true),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeader(
              extent: 72 + AppSizes.chipRowHeight(context) + AppSpacing.xs,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xs, gutter, AppSpacing.xs),
                    child: AppSearchBar(
                      hintText: l10n.librarySearchHint,
                      onChanged: ref.read(libraryFilterProvider.notifier).search,
                    ),
                  ),
                  CategoryPills(
                    categories: categories,
                    selected: filter.category,
                    onSelected: ref.read(libraryFilterProvider.notifier).selectCategory,
                  ),
                ],
              ),
            ),
          ),
          if (books.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_outlined,
                title: l10n.libraryNoMatches,
                message: l10n.libraryNoMatchesHint,
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.xxl),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = math.max(2, (width / _minTileWidth).floor());
                  final tileWidth = (width - _gridSpacing * (columns - 1)) / columns;
                  // Cover (2:3) plus the text block, which grows with the user's text scale.
                  final tileHeight = tileWidth / AppSizes.coverAspectRatio + libraryCardTextHeight * textScale;
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: _gridSpacing,
                      crossAxisSpacing: _gridSpacing,
                      mainAxisExtent: tileHeight,
                    ),
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return LibraryBookCard(book: book, onTap: () => showBookDetailsSheet(context, book));
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StickyHeader extends SliverPersistentHeaderDelegate {
  _StickyHeader({required this.extent, required this.child});

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: overlapsContent ? scheme.surfaceContainer : scheme.surface,
      elevation: overlapsContent ? AppElevation.level1 : AppElevation.level0,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyHeader old) => old.extent != extent || old.child != child;
}
