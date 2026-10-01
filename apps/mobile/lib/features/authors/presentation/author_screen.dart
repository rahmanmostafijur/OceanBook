import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../../books/data/catalog_providers.dart';
import '../../books/presentation/widgets/book_tile.dart';

/// Author profile with their published books (server-filtered by `?author=`).
class AuthorScreen extends ConsumerWidget {
  const AuthorScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final author = ref.watch(authorProvider(slug));
    final books = ref.watch(bookRailProvider(BookQuery(author: slug)));
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(title: Text(author.value?.name ?? '')),
      body: switch (author) {
        AsyncValue(:final value?) => ListView(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.sectionGap),
          children: [
            ConstrainedContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(value.name, style: theme.textTheme.headlineSmall)),
                  if (value.nameAlt != null)
                    Text(
                      value.nameAlt!,
                      style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  if (value.biography != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(value.biography!, style: theme.textTheme.bodyLarge),
                  ],
                  SectionHeader(title: l10n.authorBooks),
                  switch (books) {
                    AsyncData(:final value) when value.isEmpty => Text(l10n.emptyBooks),
                    AsyncData(:final value) => Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [for (final book in value) BookTile(book: book, width: 160)],
                    ),
                    AsyncError(:final error) => Text(failureMessage(l10n, error)),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ],
              ),
            ),
          ],
        ),
        AsyncError(:final error) => ErrorState(
          title: l10n.errorTitle,
          message: failureMessage(l10n, error),
          retryLabel: l10n.actionRetry,
          onRetry: () => ref.invalidate(authorProvider(slug)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
