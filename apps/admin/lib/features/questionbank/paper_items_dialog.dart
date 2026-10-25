import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_question_api.dart';
import 'paper_detail_page.dart' show adminPublishedQuestionsProvider;

/// Picks the questions of a paper from the published questions of its subject. Questions already in the
/// paper keep their item number and marks; new ones are numbered after the highest number in use. The
/// server still checks that every question belongs to the paper's subject and appears once.
class PaperItemsDialog extends ConsumerStatefulWidget {
  const PaperItemsDialog({required this.subjectId, required this.current, super.key});

  final String subjectId;
  final List<AdminPaperItem> current;

  @override
  ConsumerState<PaperItemsDialog> createState() => _PaperItemsDialogState();
}

class _PaperItemsDialogState extends ConsumerState<PaperItemsDialog> {
  late final Set<String> _selected = {for (final i in widget.current) i.questionId};

  List<AdminPaperItem> _result(List<AdminQuestionRow> rows) {
    final kept = [
      for (final i in widget.current)
        if (_selected.contains(i.questionId)) i,
    ];
    final keptIds = {for (final i in kept) i.questionId};
    var next = kept.fold<int>(0, (max, i) => (int.tryParse(i.itemNumber) ?? 0) > max ? int.parse(i.itemNumber) : max);
    return [
      ...kept,
      for (final row in rows)
        if (_selected.contains(row.id) && !keptIds.contains(row.id))
          AdminPaperItem(questionId: row.id, itemNumber: '${++next}'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final questions = ref.watch(adminPublishedQuestionsProvider(widget.subjectId));
    final rows = questions.value ?? const <AdminQuestionRow>[];
    return AlertDialog(
      title: Text(l10n.adminChooseQuestions),
      content: SizedBox(
        width: AppSizes.maxReadableWidth,
        child: switch (questions) {
          AsyncData(:final value) when value.isEmpty => Text(l10n.adminNoPublishedQuestions),
          AsyncData(:final value) => ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(l10n.adminChooseQuestionsHint, style: Theme.of(context).textTheme.bodySmall),
              ),
              for (final q in value)
                CheckboxListTile(
                  key: Key('pick-${q.id}'),
                  value: _selected.contains(q.id),
                  title: Text(q.stem, maxLines: 2, overflow: TextOverflow.ellipsis),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (on) => setState(() => on ?? false ? _selected.add(q.id) : _selected.remove(q.id)),
                ),
            ],
          ),
          AsyncError(:final error) => Text(adminFailureMessage(l10n, error)),
          _ => PageLoading(semanticLabel: l10n.commonLoading),
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(
          key: const Key('pick-confirm'),
          onPressed: questions.hasValue ? () => Navigator.of(context).pop(_result(rows)) : null,
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
