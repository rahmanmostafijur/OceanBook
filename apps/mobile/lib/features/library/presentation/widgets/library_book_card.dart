import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../library_labels.dart';

const int _titleMaxLines = 3;
const int _authorMaxLines = 2;
const double _badgeHeight = 22;
const double _heightSlack = 4;

/// Height the text block under a cover needs at the user's current text scale: title (up to 3 lines),
/// authors (up to 2) and the status badge, plus paddings. Ellipsis only happens beyond those line counts.
double libraryCardTextHeight(BuildContext context) {
  final text = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  double lines(TextStyle? style, int count) => scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.5) * count;
  return AppSpacing.xxs * 2 +
      AppSpacing.xs +
      lines(text.titleSmall, _titleMaxLines) +
      lines(text.bodySmall, _authorMaxLines) +
      AppSpacing.xs +
      scaler.scale(_badgeHeight) +
      _heightSlack;
}

/// Cover (with a favourite mark), title, authors and the reading status in words. One labelled button
/// for assistive tech. The grid reserves the cover's height plus [libraryCardTextHeight].
class LibraryBookCard extends StatelessWidget {
  const LibraryBookCard({required this.book, required this.onTap, super.key});

  final LibraryItem book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authors = authorsOrUnknown(l10n, book);
    final label = [
      l10n.bookCardLabel(book.title, authors),
      shelfStatusLabel(l10n, book.status),
      if (book.isFavorite) l10n.libraryFavorite,
    ].join(', ');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  BookCover(title: book.title, imageUrl: book.coverUrl),
                  if (book.isFavorite)
                    PositionedDirectional(
                      top: AppSpacing.xxs,
                      end: AppSpacing.xxs,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.9), shape: BoxShape.circle),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxs),
                          child: Icon(Icons.favorite, size: AppSizes.iconSmall, color: scheme.error),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                book.title,
                maxLines: _titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                authors,
                maxLines: _authorMaxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xs),
              ShelfStatusBadge(status: book.status),
            ],
          ),
        ),
      ),
    );
  }
}
