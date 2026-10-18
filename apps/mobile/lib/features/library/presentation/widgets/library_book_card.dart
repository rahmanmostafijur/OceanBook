import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../domain/library_book.dart';

const int _titleMaxLines = 3;
const int _authorMaxLines = 2;
const int _progressMaxLines = 2;
const double _progressBarHeight = 4;
const double _heightSlack = 4;

/// Height the text block under a cover needs at the user's current text scale: title (up to 3 lines),
/// author (up to 2), the progress bar and the progress label (up to 2), plus paddings. Ellipsis only
/// happens beyond those line counts.
double libraryCardTextHeight(BuildContext context) {
  final text = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  double lines(TextStyle? style, int count) => scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.5) * count;
  return AppSpacing.xxs * 2 +
      AppSpacing.xs +
      lines(text.titleSmall, _titleMaxLines) +
      lines(text.bodySmall, _authorMaxLines) +
      AppSpacing.xs +
      _progressBarHeight +
      AppSpacing.xxs +
      lines(text.labelSmall, _progressMaxLines) +
      _heightSlack;
}

/// Cover, thin progress bar, title, author and a progress label. One labelled button for assistive
/// tech. The grid reserves the cover's height plus [libraryCardTextHeight], so
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
              Text(
                book.title,
                maxLines: _titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Text(
                book.author,
                maxLines: _authorMaxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppShapes.extraSmall),
                child: LinearProgressIndicator(
                  value: book.progressPercent / 100,
                  minHeight: _progressBarHeight,
                  semanticsLabel: progress,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                progress,
                maxLines: _progressMaxLines,
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
