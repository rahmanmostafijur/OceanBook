import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../data/library_providers.dart';
import 'library_labels.dart';
import 'widgets/book_details_sheet.dart';
import 'widgets/filter_pills.dart';
import 'widgets/library_book_card.dart';

const double _minTileWidth = 150;
const double _gridSpacing = AppSpacing.sm;

const double _searchBarMinHeight = 56;
const double _searchTextSize = 16;
const double _searchTextLineHeight = 1.6;
const double _searchBarSlack = 8;

/// The search bar is at least 56 dp and grows with the text scale; the pinned header must reserve that.
double _searchBarHeight(BuildContext context) => math.max(
  _searchBarMinHeight,
  MediaQuery.textScalerOf(context).scale(_searchTextSize) * _searchTextLineHeight + _searchBarSlack,
);

/// Search, status filters with counts, sort and a responsive cover grid.
class BooksTab extends ConsumerStatefulWidget {
  const BooksTab({required this.books, super.key});

  final List<LibraryItem> books;

  @override
  ConsumerState<BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends ConsumerState<BooksTab> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(libraryViewProvider).query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    final l10n = ObLocalizations.of(context);
    if (books.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => runReporting(context, () => ref.refresh(libraryProvider.future)),
        child: CustomScrollView(
          // Short and empty lists still pull to refresh.
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.local_library_outlined,
                title: l10n.libraryEmptyTitle,
                message: l10n.libraryEmptyMessage,
                action: FilledButton.icon(
                  onPressed: () => context.go('/explore'),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(l10n.libraryExploreAction),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final view = ref.watch(libraryViewProvider);
    final notifier = ref.read(libraryViewProvider.notifier);
    final visible = view.apply(books);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    int count(bool Function(LibraryItem) test) => books.where(test).length;
    final filters = <(LibraryShelfFilter, String)>[
      (LibraryShelfFilter.all, l10n.libraryFilterLabel(l10n.libraryCategoryAll, books.length)),
      (
        LibraryShelfFilter.reading,
        l10n.libraryFilterLabel(l10n.libraryStatusReading, count((b) => b.status == ShelfStatus.reading)),
      ),
      (
        LibraryShelfFilter.wantToRead,
        l10n.libraryFilterLabel(l10n.libraryStatusWantToRead, count((b) => b.status == ShelfStatus.wantToRead)),
      ),
      (
        LibraryShelfFilter.finished,
        l10n.libraryFilterLabel(l10n.libraryStatusFinished, count((b) => b.status == ShelfStatus.finished)),
      ),
      (LibraryShelfFilter.favorites, l10n.libraryFilterLabel(l10n.libraryFilterFavorites, count((b) => b.isFavorite))),
    ];

    return RefreshIndicator(
      onRefresh: () => runReporting(context, () => ref.refresh(libraryProvider.future)),
      child: CustomScrollView(
        // Short and empty lists still pull to refresh.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeader(
              extent: _searchBarHeight(context) + AppSpacing.xs * 3 + AppSizes.chipRowHeight(context),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xs, gutter, AppSpacing.xs),
                    child: AppSearchBar(
                      controller: _search,
                      hintText: l10n.librarySearchHint,
                      onChanged: notifier.search,
                    ),
                  ),
                  FilterPills<LibraryShelfFilter>(
                    items: filters,
                    selected: view.filter,
                    onSelected: notifier.filter,
                    semanticLabel: l10n.libraryFiltersLabel,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xs, gutter, 0),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.libraryBookCount(visible.length),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: _SortMenu(sort: view.sort, onSelected: notifier.sortBy),
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: view.query.trim().isNotEmpty
                  ? EmptyState(
                      icon: Icons.search_off_outlined,
                      title: l10n.libraryNoMatches,
                      message: l10n.libraryNoMatchesHint,
                    )
                  : EmptyState(
                      icon: Icons.filter_list_off_outlined,
                      title: l10n.libraryFilterEmpty,
                      message: l10n.libraryFilterEmptyHint,
                    ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xs, gutter, AppSpacing.xxl),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = math.max(2, (width / _minTileWidth).floor());
                  final tileWidth = (width - _gridSpacing * (columns - 1)) / columns;
                  // Cover (2:3) plus the text block, which grows with the user's text scale.
                  final tileHeight = tileWidth / AppSizes.coverAspectRatio + libraryCardTextHeight(context);
                  return SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: _gridSpacing,
                      crossAxisSpacing: _gridSpacing,
                      mainAxisExtent: tileHeight,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final book = visible[index];
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

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onSelected});

  final LibrarySort sort;
  final ValueChanged<LibrarySort> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    String label(LibrarySort s) => switch (s) {
      LibrarySort.recentlyAdded => l10n.librarySortRecent,
      LibrarySort.recentlyUpdated => l10n.librarySortUpdated,
      LibrarySort.title => l10n.librarySortTitle,
    };
    return PopupMenuButton<LibrarySort>(
      tooltip: l10n.librarySort,
      initialValue: sort,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final s in LibrarySort.values) CheckedPopupMenuItem(value: s, checked: s == sort, child: Text(label(s))),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouchTarget),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label(sort), overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.swap_vert, size: AppSizes.iconSmall),
          ],
        ),
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
