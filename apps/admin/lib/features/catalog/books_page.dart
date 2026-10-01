import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_catalog_api.dart';
import 'new_book_dialog.dart';

const _statuses = ['draft', 'in_review', 'published', 'unpublished', 'archived'];
const _pageSize = 25;

@immutable
class BookFilter {
  const BookFilter({this.query = '', this.status, this.page = 1});

  final String query;
  final String? status;
  final int page;

  @override
  bool operator ==(Object other) =>
      other is BookFilter && other.query == query && other.status == status && other.page == page;

  @override
  int get hashCode => Object.hash(query, status, page);
}

class _Filter extends Notifier<BookFilter> {
  @override
  BookFilter build() => const BookFilter();

  void update(BookFilter filter) => state = filter;
}

final bookFilterProvider = NotifierProvider<_Filter, BookFilter>(_Filter.new);

final adminBooksProvider = FutureProvider.autoDispose<Paged<AdminBookRow>>((ref) {
  final filter = ref.watch(bookFilterProvider);
  return ref
      .watch(adminCatalogRepositoryProvider)
      .books(query: filter.query, status: filter.status, page: filter.page, pageSize: _pageSize);
});

/// Books: server-side search, status filter and paging over every book, including drafts.
class BooksPage extends ConsumerWidget {
  const BooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final filter = ref.watch(bookFilterProvider);
    final books = ref.watch(adminBooksProvider);
    final setFilter = ref.read(bookFilterProvider.notifier).update;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: AppSearchBar(
                  fieldKey: const Key('books-search'),
                  hintText: l10n.adminColumnTitle,
                  onSubmitted: (q) => setFilter(BookFilter(query: q.trim(), status: filter.status)),
                ),
              ),
              DropdownMenu<String?>(
                key: const Key('books-status'),
                initialSelection: filter.status,
                label: Text(l10n.adminColumnStatus),
                onSelected: (status) => setFilter(BookFilter(query: filter.query, status: status)),
                dropdownMenuEntries: [
                  DropdownMenuEntry(value: null, label: l10n.adminAllStatuses),
                  for (final s in _statuses) DropdownMenuEntry(value: s, label: statusLabel(l10n, s)),
                ],
              ),
              FilledButton.icon(
                key: const Key('new-book'),
                onPressed: () => showNewBookDialog(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.adminNewBook),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (books) {
              AsyncData(:final value) when value.rows.isEmpty => EmptyState(
                icon: Icons.menu_book_outlined,
                title: l10n.emptyBooks,
                message: l10n.emptyBooksHint,
              ),
              AsyncData(:final value) => _BooksTable(page: value, filter: filter, onPage: setFilter),
              AsyncError(:final error) => ErrorState(
                title: l10n.errorTitle,
                message: adminFailureMessage(l10n, error),
                retryLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(adminBooksProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _BooksTable extends StatelessWidget {
  const _BooksTable({required this.page, required this.filter, required this.onPage});

  final Paged<AdminBookRow> page;
  final BookFilter filter;
  final ValueChanged<BookFilter> onPage;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final lastPage = (page.total / _pageSize).ceil().clamp(1, 1 << 20);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: [
                    DataColumn(label: Text(l10n.adminColumnTitle)),
                    DataColumn(label: Text(l10n.adminColumnStatus)),
                    DataColumn(label: Text(l10n.adminColumnAccess)),
                    DataColumn(label: Text(l10n.adminColumnEditions), numeric: true),
                    DataColumn(label: Text(l10n.adminColumnUpdated)),
                  ],
                  rows: [
                    for (final book in page.rows)
                      DataRow(
                        onSelectChanged: (_) => context.go('/books/${book.id}'),
                        cells: [
                          DataCell(Text(book.title, overflow: TextOverflow.ellipsis)),
                          DataCell(StatusChip(status: book.status)),
                          DataCell(Text(accessLabel(l10n, book.accessLevel))),
                          DataCell(Text('${book.editionCount}')),
                          DataCell(Text(MaterialLocalizations.of(context).formatShortDate(book.updatedAt.toLocal()))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
            child: Row(
              children: [
                Text(l10n.adminResults(page.total), key: ValueKey('results-$locale')),
                const Spacer(),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                  onPressed: filter.page > 1
                      ? () => onPage(BookFilter(query: filter.query, status: filter.status, page: filter.page - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${filter.page} / $lastPage'),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                  onPressed: filter.page < lastPage
                      ? () => onPage(BookFilter(query: filter.query, status: filter.status, page: filter.page + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Workflow status as a chip with an icon, so it never relies on colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final icon = switch (status) {
      'published' => Icons.public,
      'in_review' => Icons.rate_review_outlined,
      'unpublished' || 'withdrawn' => Icons.visibility_off_outlined,
      'archived' => Icons.inventory_2_outlined,
      _ => Icons.edit_note,
    };
    // Exposed as plain text so a tappable table cell is labelled by it (a Chip is its own semantic node).
    final label = statusLabel(l10n, status);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Chip(
        avatar: Icon(icon, size: AppSizes.iconSmall),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
