import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../catalog/books_page.dart' show StatusChip;
import 'admin_question_api.dart';
import 'creative_parts.dart' show formatMarks;
import 'paper_editor_page.dart' show paperSectionLabel;
import 'paper_items_dialog.dart';
import 'papers_page.dart' show adminPapersProvider;
import 'question_detail_page.dart' show CommentDialog;
import 'question_labels.dart';

const _maxPickableQuestions = 100;

final adminPaperProvider = FutureProvider.autoDispose.family<AdminPaper, String>(
  (ref, id) => ref.watch(adminQuestionRepositoryProvider).paper(id),
);

/// The published questions of a subject, the pool a paper's questions are chosen from.
final adminPublishedQuestionsProvider = FutureProvider.autoDispose.family<List<AdminQuestionRow>, String>((
  ref,
  subjectId,
) async {
  final page = await ref
      .watch(adminQuestionRepositoryProvider)
      .questions(status: 'published', subjectId: subjectId, pageSize: _maxPickableQuestions);
  return page.rows;
});

/// One question paper for staff: its details, its questions, and the actions its state allows. The server
/// decides whether each action is permitted, including the provenance and rights publish gate.
class PaperDetailPage extends ConsumerWidget {
  const PaperDetailPage({required this.paperId, super.key});

  final String paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    return switch (ref.watch(adminPaperProvider(paperId))) {
      AsyncValue(:final value?) => _PaperView(paper: value),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminPaperProvider(paperId)),
      ),
      _ => PageLoading(semanticLabel: l10n.commonLoading),
    };
  }
}

class _PaperView extends ConsumerStatefulWidget {
  const _PaperView({required this.paper});

  final AdminPaper paper;

  @override
  ConsumerState<_PaperView> createState() => _PaperViewState();
}

class _PaperViewState extends ConsumerState<_PaperView> {
  bool _busy = false;
  String? _error;
  List<String> _blockReasons = const [];

  Future<void> _run(Future<Object?> Function(AdminQuestionRepository repo) action) async {
    final l10n = ObLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _blockReasons = const [];
    });
    try {
      await action(ref.read(adminQuestionRepositoryProvider));
      ref
        ..invalidate(adminPaperProvider(widget.paper.id))
        ..invalidate(adminPapersProvider);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = adminFailureMessage(l10n, error);
          _blockReasons = blockReasonsOf(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const CommentDialog());
    if (reason == null) return;
    await _run((repo) => repo.archivePaper(widget.paper.id, reason));
  }

  Future<void> _chooseQuestions() async {
    final subjectId = widget.paper.subjectId;
    if (subjectId == null) return;
    final items = await showDialog<List<AdminPaperItem>>(
      context: context,
      builder: (_) => PaperItemsDialog(subjectId: subjectId, current: widget.paper.items),
    );
    if (items == null) return;
    await _run((repo) => repo.setPaperItems(widget.paper.id, items));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final paper = widget.paper;
    final isDraft = paper.status == 'draft';
    final canPublish = isDraft || paper.status == 'archived';
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth + 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          '${paper.title ?? examKindLabel(l10n, paper.examKind)} · ${paper.examYear}',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    StatusChip(status: paper.status),
                  ],
                ),
                Text(
                  [
                    paperSectionLabel(l10n, paper.section),
                    if (paper.totalMarks != null) l10n.adminTotalMarks(formatMarks(paper.totalMarks!)),
                    if (paper.durationMinutes != null) '${paper.durationMinutes} min',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (canPublish)
                      FilledButton(
                        key: const Key('paper-publish'),
                        onPressed: _busy ? null : () => _run((repo) => repo.publishPaper(paper.id)),
                        child: Text(l10n.adminActionPublish),
                      ),
                    if (isDraft) ...[
                      OutlinedButton.icon(
                        key: const Key('paper-edit'),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.adminEditPaper),
                        onPressed: _busy ? null : () => context.go('/question-papers/${paper.id}/edit'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('paper-choose'),
                        icon: const Icon(Icons.checklist),
                        label: Text(l10n.adminChooseQuestions),
                        onPressed: _busy ? null : _chooseQuestions,
                      ),
                    ],
                    if (paper.status != 'archived')
                      OutlinedButton(
                        key: const Key('paper-archive'),
                        onPressed: _busy ? null : _archive,
                        child: Text(l10n.adminActionArchive),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    container: true,
                    child: Text(
                      _error!,
                      key: const Key('paper-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  for (final reason in _blockReasons) Text('• ${gateReason(l10n, reason)}'),
                ],
                SectionHeader(title: l10n.adminPaperItems),
                if (paper.items.isEmpty)
                  Text(l10n.adminNoPaperItems, style: theme.textTheme.bodyMedium)
                else
                  _ItemsList(paper: paper),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemsList extends ConsumerWidget {
  const _ItemsList({required this.paper});

  final AdminPaper paper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final subjectId = paper.subjectId;
    final stems = subjectId == null
        ? const <String, String>{}
        : {
            for (final q in ref.watch(adminPublishedQuestionsProvider(subjectId)).value ?? const <AdminQuestionRow>[])
              q.id: q.stem,
          };
    return Column(
      children: [
        for (final item in paper.items)
          ListTile(
            key: Key('paper-item-${item.itemNumber}'),
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Semantics(
                label: '${l10n.adminItemNumber} ${item.itemNumber}',
                child: ExcludeSemantics(child: Text(item.itemNumber)),
              ),
            ),
            title: Text(stems[item.questionId] ?? item.questionId, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: item.marks == null ? null : Text(l10n.questionMarks(item.marks!)),
            onTap: () => context.go('/questions/${item.questionId}'),
          ),
      ],
    );
  }
}
