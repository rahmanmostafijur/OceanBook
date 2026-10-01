import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../../../core/settings/app_settings.dart';
import '../data/catalog_providers.dart';
import 'access_panel.dart';
import 'widgets/book_tile.dart';

const _coverWidthCompact = 140.0;
const _coverWidthWide = 240.0;
const _sidePaneWidth = 300.0;

/// Book details: metadata, server access block, table of contents (Book -> Edition -> Chapter -> Section),
/// edition facts and credits. One column on phones; cover and actions in a side pane on wide windows.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.idOrSlug, super.key});

  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final detail = ref.watch(bookDetailProvider(idOrSlug));
    return Scaffold(
      appBar: AppBar(),
      body: switch (detail) {
        AsyncValue(:final value?) => _Body(book: value, returnTo: GoRouterState.of(context).uri.toString()),
        AsyncError(:final error) => ErrorState(
          title: l10n.errorTitle,
          message: failureMessage(l10n, error),
          retryLabel: l10n.actionRetry,
          onRetry: () => ref.invalidate(bookDetailProvider(idOrSlug)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.book, required this.returnTo});

  final BookDetail book;
  final String returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = WindowSize.of(context) >= WindowSize.expanded;
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final uiLocale = ref.watch(localeProvider).languageCode;
    final header = _Header(book: book, uiLocale: uiLocale, centered: !wide);
    final actions = AccessPanel(access: book.access, returnTo: returnTo);
    final details = _Details(book: book);
    if (!wide) {
      return ListView(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.sectionGap),
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          actions,
          details,
        ],
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.sectionGap),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _sidePaneWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BookCover(title: book.card.title, imageUrl: book.card.coverUrl, width: _coverWidthWide),
                    const SizedBox(height: AppSpacing.md),
                    actions,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xxl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(book: book, uiLocale: uiLocale, centered: false, showCover: false),
                    details,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.book, required this.uiLocale, required this.centered, this.showCover = true});

  final BookDetail book;
  final String uiLocale;
  final bool centered;
  final bool showCover;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final card = book.card;
    final (badge, badgeLabel) = accessBadge(l10n, card.accessLevel);
    final align = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        if (showCover) BookCover(title: card.title, imageUrl: card.coverUrl, width: _coverWidthCompact),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(card.title, textAlign: textAlign, style: theme.textTheme.headlineSmall),
        ),
        if (card.subtitle != null) Text(card.subtitle!, textAlign: textAlign, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          spacing: AppSpacing.xs,
          children: [
            for (final c in card.contributors)
              ActionChip(
                avatar: const Icon(Icons.person_outline, size: AppSizes.iconSmall),
                label: Text(c.role == 'author' ? c.name : '${c.name} · ${contributorRole(l10n, c.role)}'),
                onPressed: () => context.go('/explore/authors/${c.slug}'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AccessChip(badge: badge, label: badgeLabel),
        if (card.locale != uiLocale) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.bookShownInLanguage(card.locale == 'bn' ? l10n.languageBangla : l10n.languageEnglish),
            key: const Key('language-fallback'),
            textAlign: textAlign,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.book});

  final BookDetail book;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final edition = book.defaultEdition;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (book.description != null) ...[
          SectionHeader(title: l10n.bookAbout),
          Text(book.description!, style: theme.textTheme.bodyLarge),
        ],
        if (book.toc.isNotEmpty) ...[
          SectionHeader(title: '${l10n.bookContents} · ${l10n.bookChapterCount(book.toc.length)}'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [for (final chapter in book.toc) _ChapterTile(chapter: chapter)]),
          ),
        ],
        if (edition != null) ...[
          SectionHeader(title: l10n.bookDetails),
          _Fact(label: l10n.bookEdition, value: edition.label),
          if (edition.publishers.isNotEmpty)
            _Fact(label: l10n.bookPublisher, value: edition.publishers.map((p) => p.name).join(', ')),
          if (edition.isbn13 != null) _Fact(label: l10n.bookIsbn, value: edition.isbn13!),
          if (edition.pageCount != null) _Fact(label: l10n.bookPages, value: '${edition.pageCount}'),
          _Fact(
            label: l10n.bookLanguage,
            value: edition.language == 'bn'
                ? l10n.languageBangla
                : (edition.language == 'en' ? l10n.languageEnglish : edition.language),
          ),
          if (edition.publicationDate != null)
            _Fact(label: l10n.bookPublished, value: '${edition.publicationDate!.year}'),
        ],
        if (book.categories.isNotEmpty) ...[
          SectionHeader(title: l10n.categoriesTitle),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final c in book.categories) Chip(label: Text(c.name))],
          ),
        ],
        if (book.attributions.isNotEmpty) ...[
          SectionHeader(title: l10n.bookCredits),
          for (final line in book.attributions)
            Text(line, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({required this.chapter});

  final TocChapter chapter;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final badge = chapter.hasPreview ? AccessChip(badge: AccessBadge.preview, label: l10n.bookPreviewBadge) : null;
    if (chapter.sections.isEmpty) return ListTile(title: Text(chapter.title), trailing: badge);
    return ExpansionTile(
      title: Text(chapter.title),
      trailing: badge,
      children: [
        for (final section in chapter.sections)
          ListTile(
            contentPadding: const EdgeInsetsDirectional.only(start: AppSpacing.xxl, end: AppSpacing.md),
            title: Text(section.title),
            trailing: section.isPreview ? const Icon(Icons.visibility_outlined, size: AppSizes.iconSmall) : null,
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
