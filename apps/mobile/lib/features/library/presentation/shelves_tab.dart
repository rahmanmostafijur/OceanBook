import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../data/library_providers.dart';
import 'library_labels.dart';
import 'widgets/shelf_dialogs.dart';

const double _previewCoverWidth = 40;
const int _previewCovers = 3;

/// The user's shelves as cards with a cover preview; tap to open, menu to edit or delete.
class ShelvesTab extends ConsumerWidget {
  const ShelvesTab({required this.books, super.key});

  final List<LibraryItem> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final shelves = ref.watch(collectionsProvider);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final byId = {for (final b in books) b.bookId: b};
    final newShelf = FloatingActionButton.extended(
      heroTag: 'new-shelf',
      onPressed: () => showShelfEditor(context),
      icon: const Icon(Icons.add),
      label: Text(l10n.shelvesNew),
    );
    return Scaffold(
      floatingActionButton: newShelf,
      body: switch (shelves) {
        AsyncValue(:final value?) when value.isEmpty => EmptyState(
          icon: Icons.shelves,
          title: l10n.shelvesEmptyTitle,
          message: l10n.shelvesEmptyMessage,
        ),
        AsyncValue(:final value?) => RefreshIndicator(
          onRefresh: () => runReporting(context, () => ref.refresh(collectionsProvider.future)),
          child: ConstrainedContent(
            maxWidth: AppSizes.maxReadableWidth,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              // Leave room for the floating button under the last card.
              padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.giant + AppSpacing.xxl),
              itemCount: value.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter == AppSpacing.md ? 0 : AppSpacing.xxs),
                    child: Text(l10n.shelvesCount(value.length), style: Theme.of(context).textTheme.labelLarge),
                  );
                }
                final shelf = value[index - 1];
                return ShelfCard(
                  shelf: shelf,
                  covers: [
                    for (final id in shelf.bookIds.take(_previewCovers))
                      if (byId[id] != null) byId[id]!,
                  ],
                );
              },
            ),
          ),
        ),
        AsyncError(:final error) => ErrorState(
          title: l10n.errorTitle,
          message: failureMessage(l10n, error),
          retryLabel: l10n.actionRetry,
          onRetry: () => ref.invalidate(collectionsProvider),
        ),
        _ => PageLoading(semanticLabel: l10n.commonLoading),
      },
    );
  }
}

class ShelfCard extends ConsumerWidget {
  const ShelfCard({required this.shelf, required this.covers, super.key});

  final BookCollection shelf;
  final List<LibraryItem> covers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.large),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/library/shelves/${shelf.id}'),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.xxs, AppSpacing.md),
          child: Row(
            children: [
              ExcludeSemantics(child: _CoverStack(covers: covers)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shelf.name, style: theme.textTheme.titleMedium),
                    Text(
                      l10n.libraryBookCount(shelf.bookCount),
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (shelf.description != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        shelf.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              ShelfMenu(shelf: shelf),
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to three overlapping covers, or a shelf icon for an empty shelf.
class _CoverStack extends StatelessWidget {
  const _CoverStack({required this.covers});

  final List<LibraryItem> covers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const height = _previewCoverWidth / AppSizes.coverAspectRatio;
    if (covers.isEmpty) {
      return Container(
        width: _previewCoverWidth * 1.6,
        height: height,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppShapes.medium),
        ),
        child: Icon(Icons.shelves, color: scheme.onSecondaryContainer),
      );
    }
    const offset = _previewCoverWidth * 0.3;
    return SizedBox(
      width: _previewCoverWidth + offset * (_previewCovers - 1),
      height: height,
      child: Stack(
        children: [
          for (final (i, book) in covers.indexed.toList().reversed)
            PositionedDirectional(
              start: offset * i,
              // A surface-coloured edge keeps overlapping covers apart.
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: AppShapes.cover,
                  border: Border.all(color: scheme.surfaceContainerLow, width: 1.5),
                ),
                child: BookCover(title: book.title, imageUrl: book.coverUrl, width: _previewCoverWidth),
              ),
            ),
        ],
      ),
    );
  }
}

/// Edit / delete for one shelf. Delete asks first and keeps the books in the library.
class ShelfMenu extends ConsumerWidget {
  const ShelfMenu({required this.shelf, this.onDeleted, super.key});

  final BookCollection shelf;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: l10n.shelfOptions(shelf.name),
      onSelected: (action) async {
        if (action == 'edit') {
          await showShelfEditor(context, existing: shelf);
          return;
        }
        final confirmed = await confirmDestructive(
          context,
          title: l10n.shelfDeleteConfirmTitle(shelf.name),
          message: l10n.shelfDeleteConfirmMessage,
          confirmLabel: l10n.shelfDeleteAction,
        );
        if (!confirmed || !context.mounted) return;
        final deleted = await runReporting(
          context,
          () => ref.read(collectionsProvider.notifier).delete(shelf.id),
          success: l10n.shelfDeleted,
        );
        if (deleted) onDeleted?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(l10n.shelfEdit)),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(leading: const Icon(Icons.delete_outline), title: Text(l10n.shelfDelete)),
        ),
      ],
    );
  }
}
