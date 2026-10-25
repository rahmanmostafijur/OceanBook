import 'dart:ui' show ImageFilter;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../data/library_providers.dart';
import '../library_labels.dart';
import 'shelf_dialogs.dart';

const double _coverWidth = 132;
const double _backdropBlur = 28;

/// Opens the details sheet for [book]: reading status, favourite, shelves, dates and the way to the
/// book page. The sheet drags between 60 % and 95 % of the screen.
Future<void> showBookDetailsSheet(BuildContext context, LibraryItem book) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  sheetAnimationStyle: AppMotion.reduced(context) ? AnimationStyle.noAnimation : null,
  useSafeArea: true,
  showDragHandle: false,
  constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth),
  shape: AppShapes.bottomSheet,
  clipBehavior: Clip.antiAlias,
  builder: (_) => BookDetailsSheet(bookId: book.bookId, initial: book),
);

/// Follows the live library entry, so every change made here (or elsewhere) shows at once.
class BookDetailsSheet extends ConsumerWidget {
  const BookDetailsSheet({required this.bookId, required this.initial, super.key});

  final String bookId;
  final LibraryItem initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = ObLocalizations.of(context);
    final book = ref.watch(libraryItemProvider(bookId)) ?? initial;
    final dates = [
      l10n.libraryAddedOn(shortDate(context, book.addedAt)),
      if (book.startedAt != null) l10n.libraryStartedOn(shortDate(context, book.startedAt!)),
      if (book.finishedAt != null) l10n.libraryFinishedOn(shortDate(context, book.finishedAt!)),
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => Stack(
        children: [
          Positioned.fill(child: _BlurredBackdrop(book: book)),
          Column(
            children: [
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // The handle is decorative; the close button is the accessible way out.
                        ExcludeSemantics(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: IconButton(
                            tooltip: l10n.actionClose,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: AppShapes.cover,
                          boxShadow: [
                            BoxShadow(
                              color: theme.shadowColor.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: BookCover(title: book.title, imageUrl: book.coverUrl, width: _coverWidth),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Semantics(
                      header: true,
                      child: Text(book.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      authorsOrUnknown(l10n, book),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (book.ratingCount > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Center(child: RatingStars(rating: book.ratingAvg)),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    SectionHeaderLabel(l10n.libraryStatusLabel),
                    _StatusPicker(book: book),
                    const SizedBox(height: AppSpacing.sm),
                    _FavoriteToggle(book: book),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dates.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SectionHeaderLabel(l10n.libraryTabShelves),
                    _ShelfChips(book: book),
                    const SizedBox(height: AppSpacing.xl),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('library-remove'),
                        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                        onPressed: () => _remove(context, ref, book),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.libraryRemove),
                      ),
                    ),
                  ],
                ),
              ),
              _PinnedAction(book: book),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, LibraryItem book) async {
    final l10n = ObLocalizations.of(context);
    final confirmed = await confirmDestructive(
      context,
      title: l10n.libraryRemoveConfirmTitle,
      message: l10n.libraryRemoveConfirmMessage(book.title),
      confirmLabel: l10n.libraryRemoveAction,
    );
    if (!confirmed || !context.mounted) return;
    final removed = await runReporting(
      context,
      () => ref.read(libraryProvider.notifier).remove(book.bookId),
      success: l10n.libraryRemoved,
    );
    // The sheet may already be gone (dismissed while the call ran); never pop the page beneath it.
    if (removed && context.mounted) Navigator.of(context).pop();
  }
}

class _StatusPicker extends ConsumerWidget {
  const _StatusPicker({required this.book});

  final LibraryItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    // Chips rather than a segmented button: they wrap instead of clipping at large text sizes.
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final status in ShelfStatus.values)
          ChoiceChip(
            avatar: Icon(shelfStatusIcon(status), size: AppSizes.iconSmall),
            showCheckmark: false,
            label: Text(shelfStatusLabel(l10n, status)),
            selected: book.status == status,
            onSelected: (_) {
              if (book.status == status) return;
              runReporting(context, () => ref.read(libraryProvider.notifier).save(book.bookId, status: status));
            },
          ),
      ],
    );
  }
}

class _FavoriteToggle extends ConsumerWidget {
  const _FavoriteToggle({required this.book});

  final LibraryItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      key: const Key('library-favorite'),
      onPressed: () => runReporting(
        context,
        () => ref.read(libraryProvider.notifier).save(book.bookId, isFavorite: !book.isFavorite),
      ),
      icon: Icon(
        book.isFavorite ? Icons.favorite : Icons.favorite_border,
        color: book.isFavorite ? scheme.error : null,
      ),
      label: Text(book.isFavorite ? l10n.libraryUnmarkFavorite : l10n.libraryMarkFavorite),
    );
  }
}

/// One chip per shelf; selected chips are the shelves this book is on.
class _ShelfChips extends ConsumerWidget {
  const _ShelfChips({required this.book});

  final LibraryItem book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final state = ref.watch(collectionsProvider);
    final shelves = state.value;
    if (shelves == null) {
      // Until shelves load, offer nothing that would act on an incomplete list.
      return state.hasError
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => ref.invalidate(collectionsProvider),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.actionRetry),
              ),
            )
          : const LinearProgressIndicator();
    }
    final controller = ref.read(collectionsProvider.notifier);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (shelves.isEmpty) Text(l10n.shelfNone, style: Theme.of(context).textTheme.bodyMedium),
        for (final shelf in shelves)
          FilterChip(
            label: Text(shelf.name),
            selected: shelf.contains(book.bookId),
            onSelected: (add) => runReporting(
              context,
              () => add ? controller.addBook(shelf.id, book.bookId) : controller.removeBook(shelf.id, book.bookId),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: AppSizes.iconSmall),
          label: Text(l10n.shelvesNew),
          onPressed: () async {
            final created = await showShelfEditor(context);
            if (created != null && context.mounted) {
              await runReporting(context, () => controller.addBook(created.id, book.bookId));
            }
          },
        ),
      ],
    );
  }
}

/// The way on to the catalog page (access, reading, contents) stays reachable without scrolling.
class _PinnedAction extends StatelessWidget {
  const _PinnedAction({required this.book});

  final LibraryItem book;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: AppElevation.level1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/explore/books/${Uri.encodeComponent(book.slug)}');
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.libraryOpenBookPage),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppSizes.minTouchTarget + 8)),
          ),
        ),
      ),
    );
  }
}

/// The cover, scaled up and blurred, behind a scrim that fades into the sheet surface.
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.book});

  final LibraryItem book;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: surface),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 420,
              width: double.infinity,
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: _backdropBlur, sigmaY: _backdropBlur, tileMode: TileMode.clamp),
                  child: Transform.scale(
                    scale: 2.2,
                    child: BookCover(title: book.title, imageUrl: book.coverUrl),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.35, 0.6],
                  colors: [surface.withValues(alpha: 0.55), surface.withValues(alpha: 0.85), surface],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeaderLabel extends StatelessWidget {
  const SectionHeaderLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Semantics(header: true, child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
  );
}

/// Five stars in half steps. The row is one labelled image for assistive tech.
class RatingStars extends StatelessWidget {
  const RatingStars({required this.rating, this.size = 24, super.key});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final premium = AppSemanticColors.of(context).premium;
    final label = l10n.bookRating(rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1));
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              Icon(
                rating >= i
                    ? Icons.star_rounded
                    : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
                size: size,
                color: rating >= i - 0.5 ? premium : scheme.outline,
              ),
            const SizedBox(width: AppSpacing.xs),
            Text(rating.toStringAsFixed(1), style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
