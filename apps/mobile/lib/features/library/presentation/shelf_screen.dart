import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../data/library_providers.dart';
import 'library_labels.dart';
import 'shelves_tab.dart';
import 'widgets/book_details_sheet.dart';

const double _rowCoverWidth = 44;

/// One shelf: its books in shelf order, with add and remove.
class ShelfScreen extends ConsumerWidget {
  const ShelfScreen({required this.shelfId, super.key});

  final String shelfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final shelves = ref.watch(collectionsProvider);
    final library = ref.watch(libraryProvider);
    if (shelves.hasError || library.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          title: l10n.errorTitle,
          message: failureMessage(l10n, (shelves.error ?? library.error)!),
          retryLabel: l10n.actionRetry,
          onRetry: () => ref
            ..invalidate(collectionsProvider)
            ..invalidate(libraryProvider),
        ),
      );
    }
    final allShelves = shelves.value;
    final books = library.value;
    if (allShelves == null || books == null) {
      return Scaffold(
        appBar: AppBar(),
        body: PageLoading(semanticLabel: l10n.commonLoading),
      );
    }
    final shelf = allShelves.where((s) => s.id == shelfId).firstOrNull;
    if (shelf == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(icon: Icons.shelves, title: l10n.errorNotFound),
      );
    }
    final byId = {for (final b in books) b.bookId: b};
    final items = [
      for (final id in shelf.bookIds)
        if (byId[id] != null) byId[id]!,
    ];
    final addBooks = FilledButton.tonalIcon(
      onPressed: () => _showPicker(context, shelf),
      icon: const Icon(Icons.playlist_add),
      label: Text(l10n.shelfAddBooks),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(shelf.name),
        actions: [
          IconButton(
            tooltip: l10n.shelfAddBooks,
            onPressed: () => _showPicker(context, shelf),
            icon: const Icon(Icons.playlist_add),
          ),
          ShelfMenu(shelf: shelf, onDeleted: () => context.go('/library')),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.shelves,
              title: l10n.shelfEmptyTitle,
              message: l10n.shelfEmptyMessage,
              action: addBooks,
            )
          : ConstrainedContent(
              maxWidth: AppSizes.maxReadableWidth,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                children: [
                  if (shelf.description != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(shelf.description!, style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  Text(l10n.libraryBookCount(items.length), style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  for (final book in items) _ShelfBookRow(shelf: shelf, book: book),
                ],
              ),
            ),
    );
  }

  Future<void> _showPicker(BuildContext context, BookCollection shelf) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: AppMotion.reduced(context) ? AnimationStyle.noAnimation : null,
    constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth),
    builder: (_) => _ShelfPicker(shelfId: shelf.id),
  );
}

class _ShelfBookRow extends ConsumerWidget {
  const _ShelfBookRow({required this.shelf, required this.book});

  final BookCollection shelf;
  final LibraryItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => showBookDetailsSheet(context, book),
      leading: BookCover(title: book.title, imageUrl: book.coverUrl, width: _rowCoverWidth),
      title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(authorsOrUnknown(l10n, book), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.xxs),
          ShelfStatusBadge(status: book.status),
        ],
      ),
      trailing: IconButton(
        tooltip: l10n.shelfRemoveBook,
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => runReporting(
          context,
          () => ref.read(collectionsProvider.notifier).removeBook(shelf.id, book.bookId),
        ),
      ),
    );
  }
}

/// Every library book with a checkbox: ticking adds it to the shelf, unticking removes it.
class _ShelfPicker extends ConsumerWidget {
  const _ShelfPicker({required this.shelfId});

  final String shelfId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final shelf = ref.watch(collectionsProvider).value?.where((s) => s.id == shelfId).firstOrNull;
    final books = ref.watch(libraryProvider).value ?? const <LibraryItem>[];
    if (shelf == null) return const SizedBox.shrink();
    final controller = ref.read(collectionsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Semantics(
            header: true,
            child: Text(l10n.shelfPickerTitle(shelf.name), style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Flexible(
          child: books.isEmpty
              ? EmptyState(icon: Icons.local_library_outlined, title: l10n.shelfPickerLibraryEmpty)
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final book in books)
                      CheckboxListTile(
                        value: shelf.contains(book.bookId),
                        secondary: BookCover(title: book.title, imageUrl: book.coverUrl, width: 32),
                        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(authorsOrUnknown(l10n, book), maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (add) => runReporting(
                          context,
                          () => add == true
                              ? controller.addBook(shelf.id, book.bookId)
                              : controller.removeBook(shelf.id, book.bookId),
                        ),
                      ),
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.shelfDone)),
          ),
        ),
      ],
    );
  }
}
