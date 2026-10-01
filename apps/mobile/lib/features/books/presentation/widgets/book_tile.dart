import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// Display mapping for the server's access level. Display only: the decision itself is the server's.
(AccessBadge, String) accessBadge(ObLocalizations l10n, AccessLevel level) => switch (level) {
  AccessLevel.free => (AccessBadge.free, l10n.bookFree),
  AccessLevel.registered => (AccessBadge.free, l10n.bookRegistered),
  AccessLevel.entitled || AccessLevel.unknown => (AccessBadge.premium, l10n.bookPremium),
};

String contributorRole(ObLocalizations l10n, String role) => switch (role) {
  'editor' => l10n.bookRoleEditor,
  'translator' => l10n.bookRoleTranslator,
  'illustrator' => l10n.bookRoleIllustrator,
  'contributor' => l10n.bookRoleContributor,
  _ => '',
};

String authorLine(BookCard book) => book.authors.map((a) => a.name).join(', ');

String bookPath(BookCard book) => '/explore/books/${book.id}';

/// Cover, title, authors and access chip; one labelled button for assistive tech.
class BookTile extends StatelessWidget {
  const BookTile({required this.book, this.width, super.key});

  final BookCard book;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final (badge, badgeLabel) = accessBadge(l10n, book.accessLevel);
    final authors = authorLine(book);
    return Semantics(
      button: true,
      label: '${l10n.bookCardLabel(book.title, authors)}, $badgeLabel',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppShapes.medium),
        onTap: () => context.go(bookPath(book)),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            // In a fixed-height grid cell the cover takes whatever height the text leaves, so large text
            // scales never overflow; in rails (unbounded height) the tile takes its natural height.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cover = BookCover(title: book.title, imageUrl: book.coverUrl);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (constraints.hasBoundedHeight)
                      Expanded(
                        child: Align(alignment: AlignmentDirectional.topStart, child: cover),
                      )
                    else
                      cover,
                    const SizedBox(height: AppSpacing.xs),
                    Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    if (authors.isNotEmpty)
                      Text(
                        authors,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: AppSpacing.xxs),
                    AccessChip(badge: badge, label: badgeLabel),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
