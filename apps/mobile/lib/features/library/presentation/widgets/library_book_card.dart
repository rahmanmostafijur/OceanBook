import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../domain/library_book.dart';

/// Space the text under a cover needs at 1x scale: title (2 lines), author, progress label and bar.
const double libraryCardTextHeight = 112;

/// Cover, thin progress bar, title, author and a progress label. One labelled button for assistive
/// tech. The grid reserves the cover's height plus [libraryCardTextHeight] scaled by the text scale, so
/// the text sits right under the cover and any spare height falls below the card.
class LibraryBookCard extends StatelessWidget {
  const LibraryBookCard({required this.book, required this.onTap, super.key});

  final LibraryBook book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = l10n.libraryProgress(book.progressPercent);
    return Semantics(
      button: true,
      label: '${l10n.bookCardLabel(book.title, book.author)}, $progress',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(title: book.title, imageUrl: book.coverUrl),
              const SizedBox(height: AppSpacing.xs),
              Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppShapes.extraSmall),
                child: LinearProgressIndicator(value: book.progressPercent / 100, minHeight: 4),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                progress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
