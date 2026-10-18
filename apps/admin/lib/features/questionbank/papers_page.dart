import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../../core/scrollable_table.dart';
import '../catalog/admin_catalog_api.dart' show Paged;
import '../catalog/books_page.dart' show StatusChip;
import 'admin_question_api.dart';
import 'question_labels.dart';

const _statuses = ['draft', 'published', 'archived'];
const _pageSize = 25;

class _PaperQuery {
  const _PaperQuery({this.status, this.page = 1});

  final String? status;
  final int page;

  @override
  bool operator ==(Object other) => other is _PaperQuery && other.status == status && other.page == page;

  @override
  int get hashCode => Object.hash(status, page);
}

class _Query extends Notifier<_PaperQuery> {
  @override
  _PaperQuery build() => const _PaperQuery();

  void update(_PaperQuery query) => state = query;
}

final _paperQueryProvider = NotifierProvider<_Query, _PaperQuery>(_Query.new);

final adminPapersProvider = FutureProvider.autoDispose<Paged<AdminPaper>>((ref) {
  final query = ref.watch(_paperQueryProvider);
  return ref.watch(adminQuestionRepositoryProvider).papers(status: query.status, page: query.page, pageSize: _pageSize);
});

/// Question papers (historical board and test papers): status filter and paging.
class PapersPage extends ConsumerWidget {
  const PapersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final query = ref.watch(_paperQueryProvider);
    final papers = ref.watch(adminPapersProvider);
    final setQuery = ref.read(_paperQueryProvider.notifier).update;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DropdownMenu<String?>(
              key: const Key('papers-status'),
              initialSelection: query.status,
              label: Text(l10n.adminColumnStatus),
              onSelected: (status) => setQuery(_PaperQuery(status: status)),
              dropdownMenuEntries: [
                DropdownMenuEntry(value: null, label: l10n.adminAllStatuses),
                for (final s in _statuses) DropdownMenuEntry(value: s, label: statusLabel(l10n, s)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (papers) {
              AsyncData(:final value) when value.rows.isEmpty => EmptyState(
                icon: Icons.description_outlined,
                title: l10n.adminNoPapers,
              ),
              AsyncData(:final value) => _PapersTable(page: value, query: query, onPage: setQuery),
              AsyncError(:final error) => ErrorState(
                title: l10n.errorTitle,
                message: adminFailureMessage(l10n, error),
                retryLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(adminPapersProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _PapersTable extends StatelessWidget {
  const _PapersTable({required this.page, required this.query, required this.onPage});

  final Paged<AdminPaper> page;
  final _PaperQuery query;
  final ValueChanged<_PaperQuery> onPage;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final lastPage = (page.total / _pageSize).ceil().clamp(1, 1 << 20);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ScrollableTable(
              child: DataTable(
                columns: [
                  DataColumn(label: Text(l10n.filterYear), numeric: true),
                  DataColumn(label: Text(l10n.adminColumnExam)),
                  DataColumn(label: Text(l10n.adminColumnStatus)),
                  DataColumn(label: Text(l10n.adminColumnBoards), numeric: true),
                  DataColumn(label: Text(l10n.adminColumnQuestions), numeric: true),
                ],
                rows: [
                  for (final paper in page.rows)
                    DataRow(
                      cells: [
                        DataCell(Text('${paper.examYear}')),
                        DataCell(Text(paper.title ?? examKindLabel(l10n, paper.examKind))),
                        DataCell(StatusChip(status: paper.status)),
                        DataCell(Text('${paper.boardCount}')),
                        DataCell(Text('${paper.itemCount}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xxs),
            child: Row(
              children: [
                Text(l10n.adminResults(page.total)),
                const Spacer(),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).previousPageTooltip,
                  onPressed: query.page > 1
                      ? () => onPage(_PaperQuery(status: query.status, page: query.page - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(l10n.adminPageOf(query.page, lastPage)),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                  onPressed: query.page < lastPage
                      ? () => onPage(_PaperQuery(status: query.status, page: query.page + 1))
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
