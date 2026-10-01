import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../data/catalog_providers.dart';
import 'explore_controller.dart';
import 'widgets/book_tile.dart';

const _searchDebounce = Duration(milliseconds: 350);
const _loadMoreExtent = 600.0;

/// Tile width target per window size; the grid fits as many columns as the width allows.
double _tileExtent(WindowSize size) => switch (size) {
  WindowSize.compact => 180,
  WindowSize.medium => 200,
  _ => 220,
};

/// Explore: search, category filter, sort, and an infinite grid of published books.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () => ref.read(exploreControllerProvider.notifier).search(text));
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _loadMoreExtent) {
      ref.read(exploreControllerProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final explore = ref.watch(exploreControllerProvider);
    final controller = ref.read(exploreControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navExplore),
        actions: [_SortMenu(current: explore.value?.query.sort ?? BookSort.newest, onSelected: controller.sortBy)],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.gutter(MediaQuery.sizeOf(context).width),
                    AppSpacing.xs,
                    AppSpacing.gutter(MediaQuery.sizeOf(context).width),
                    AppSpacing.xs,
                  ),
                  child: AppSearchBar(
                    fieldKey: const Key('catalog-search'),
                    hintText: l10n.searchHint,
                    onChanged: _onSearchChanged,
                    onSubmitted: controller.search,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _CategoryChips(selected: explore.value?.query.category, onSelected: controller.selectCategory),
              ),
              ..._results(context, l10n, explore, controller),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _results(
    BuildContext context,
    ObLocalizations l10n,
    AsyncValue<ExploreState> explore,
    ExploreController controller,
  ) {
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    return switch (explore) {
      AsyncData(:final value) when value.items.isEmpty => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(icon: Icons.menu_book_outlined, title: l10n.emptyBooks, message: l10n.emptyBooksHint),
        ),
      ],
      AsyncValue(:final value?) => [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _tileExtent(WindowSize.of(context)),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.48,
            ),
            itemCount: value.items.length,
            itemBuilder: (_, index) => BookTile(book: value.items[index]),
          ),
        ),
        SliverToBoxAdapter(
          child: _Footer(state: value, onRetry: controller.loadMore),
        ),
      ],
      AsyncError(:final error) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            title: l10n.errorTitle,
            message: failureMessage(l10n, error),
            retryLabel: l10n.actionRetry,
            onRetry: controller.refresh,
          ),
        ),
      ],
      _ => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
    };
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onRetry});

  final ExploreState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
        ),
      );
    }
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: AppSpacing.sectionGap);
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.current, required this.onSelected});

  final BookSort current;
  final ValueChanged<BookSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    String label(BookSort sort) => switch (sort) {
      BookSort.newest => l10n.catalogSortNewest,
      BookSort.popular => l10n.catalogSortPopular,
      BookSort.rating => l10n.catalogSortRating,
    };
    return PopupMenuButton<BookSort>(
      tooltip: l10n.catalogSortLabel,
      icon: const Icon(Icons.sort),
      initialValue: current,
      onSelected: onSelected,
      itemBuilder: (_) => [for (final sort in BookSort.values) PopupMenuItem(value: sort, child: Text(label(sort)))],
    );
  }
}

/// Top-level categories as filter chips; a category includes its whole subtree on the server.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final roots = (ref.watch(categoriesProvider).value ?? const <CategoryNode>[]).where((c) => c.depth == 0).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    if (roots.isEmpty) return const SizedBox.shrink();
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    return SizedBox(
      height: AppSizes.minTouchTarget + AppSpacing.xs,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        children: [
          _chip(l10n.catalogAll, selected == null, () => onSelected(null)),
          for (final category in roots)
            _chip(category.name, selected == category.slug, () => onSelected(category.slug)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool isSelected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.xs),
    child: Center(
      child: ChoiceChip(label: Text(label), selected: isSelected, onSelected: (_) => onTap()),
    ),
  );
}
