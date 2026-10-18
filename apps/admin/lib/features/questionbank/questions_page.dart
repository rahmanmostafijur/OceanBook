import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../../core/scrollable_table.dart';
import '../catalog/admin_catalog_api.dart' show Paged;
import '../catalog/books_page.dart' show StatusChip;
import 'admin_question_api.dart';
import 'question_labels.dart';

const _statuses = ['draft', 'in_review', 'changes_requested', 'approved', 'published', 'archived'];
const _pageSize = 25;

@immutable
class QuestionFilter {
  const QuestionFilter({this.status, this.type, this.needsReview = false, this.page = 1});

  final String? status;
  final QuestionType? type;
  final bool needsReview;
  final int page;

  QuestionFilter copyWith({
    String? status,
    QuestionType? type,
    bool? needsReview,
    int? page,
    bool clearStatus = false,
    bool clearType = false,
  }) => QuestionFilter(
    status: clearStatus ? null : (status ?? this.status),
    type: clearType ? null : (type ?? this.type),
    needsReview: needsReview ?? this.needsReview,
    page: page ?? 1,
  );

  @override
  bool operator ==(Object other) =>
      other is QuestionFilter &&
      other.status == status &&
      other.type == type &&
      other.needsReview == needsReview &&
      other.page == page;

  @override
  int get hashCode => Object.hash(status, type, needsReview, page);
}

class _Filter extends Notifier<QuestionFilter> {
  @override
  QuestionFilter build() => const QuestionFilter();

  void update(QuestionFilter filter) => state = filter;
}

final questionFilterProvider = NotifierProvider<_Filter, QuestionFilter>(_Filter.new);

final adminQuestionsProvider = FutureProvider.autoDispose<Paged<AdminQuestionRow>>((ref) {
  final filter = ref.watch(questionFilterProvider);
  return ref
      .watch(adminQuestionRepositoryProvider)
      .questions(
        status: filter.status,
        type: filter.type,
        needsReview: filter.needsReview,
        page: filter.page,
        pageSize: _pageSize,
      );
});

/// Questions: server-side status and type filters, a "needs review" queue and paging over every
/// question, including drafts and edits of published ones.
class QuestionsPage extends ConsumerWidget {
  const QuestionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final filter = ref.watch(questionFilterProvider);
    final questions = ref.watch(adminQuestionsProvider);
    final setFilter = ref.read(questionFilterProvider.notifier).update;
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
              DropdownMenu<String?>(
                key: const Key('questions-status'),
                initialSelection: filter.status,
                label: Text(l10n.adminColumnStatus),
                onSelected: (status) => setFilter(filter.copyWith(status: status, clearStatus: status == null)),
                dropdownMenuEntries: [
                  DropdownMenuEntry(value: null, label: l10n.adminAllStatuses),
                  for (final s in _statuses) DropdownMenuEntry(value: s, label: statusLabel(l10n, s)),
                ],
              ),
              DropdownMenu<QuestionType?>(
                key: const Key('questions-type'),
                initialSelection: filter.type,
                label: Text(l10n.adminColumnType),
                onSelected: (type) => setFilter(filter.copyWith(type: type, clearType: type == null)),
                dropdownMenuEntries: [
                  DropdownMenuEntry(value: null, label: l10n.filterAny),
                  for (final t in QuestionType.values)
                    if (t != QuestionType.unknown) DropdownMenuEntry(value: t, label: adminQuestionTypeLabel(l10n, t)),
                ],
              ),
              FilterChip(
                key: const Key('questions-needs-review'),
                label: Text(l10n.adminNeedsReview),
                selected: filter.needsReview,
                onSelected: (value) => setFilter(filter.copyWith(needsReview: value)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (questions) {
              AsyncData(:final value) when value.rows.isEmpty => EmptyState(
                icon: Icons.quiz_outlined,
                title: l10n.emptyQuestions,
                message: l10n.emptyQuestionsHint,
              ),
              AsyncData(:final value) => _QuestionsTable(page: value, filter: filter, onPage: setFilter),
              AsyncError(:final error) => ErrorState(
                title: l10n.errorTitle,
                message: adminFailureMessage(l10n, error),
                retryLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(adminQuestionsProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _QuestionsTable extends StatelessWidget {
  const _QuestionsTable({required this.page, required this.filter, required this.onPage});

  final Paged<AdminQuestionRow> page;
  final QuestionFilter filter;
  final ValueChanged<QuestionFilter> onPage;

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
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: Text(l10n.adminColumnStem)),
                  DataColumn(label: Text(l10n.adminColumnType)),
                  DataColumn(label: Text(l10n.adminColumnStatus)),
                  DataColumn(label: Text(l10n.adminColumnMarks), numeric: true),
                  DataColumn(label: Text(l10n.adminColumnUpdated)),
                ],
                rows: [
                  for (final q in page.rows)
                    DataRow(
                      onSelectChanged: (_) => context.go('/questions/${q.id}'),
                      cells: [
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        DataCell(Text(adminQuestionTypeLabel(l10n, q.type))),
                        DataCell(StatusChip(status: q.pendingStatus ?? q.status)),
                        DataCell(Text(q.marks == q.marks.roundToDouble() ? '${q.marks.round()}' : '${q.marks}')),
                        DataCell(Text(MaterialLocalizations.of(context).formatShortDate(q.updatedAt.toLocal()))),
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
                  onPressed: filter.page > 1 ? () => onPage(filter.copyWith(page: filter.page - 1)) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(l10n.adminPageOf(filter.page, lastPage)),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                  onPressed: filter.page < lastPage ? () => onPage(filter.copyWith(page: filter.page + 1)) : null,
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
