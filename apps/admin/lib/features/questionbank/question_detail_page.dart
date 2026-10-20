import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../catalog/books_page.dart' show StatusChip;
import 'admin_question_api.dart';
import 'question_labels.dart';
import 'questions_page.dart' show adminQuestionsProvider;

final adminQuestionProvider = FutureProvider.autoDispose.family<AdminQuestion, String>(
  (ref, id) => ref.watch(adminQuestionRepositoryProvider).question(id),
);

/// One question for staff: the latest revision, the server's completeness issues, and the workflow
/// actions its state allows. The server decides whether each action is permitted (permissions,
/// separation of duties, the provenance publish gate).
class QuestionDetailPage extends ConsumerWidget {
  const QuestionDetailPage({required this.questionId, super.key});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    return switch (ref.watch(adminQuestionProvider(questionId))) {
      AsyncValue(:final value?) => _QuestionView(question: value),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminQuestionProvider(questionId)),
      ),
      _ => PageLoading(semanticLabel: ObLocalizations.of(context).commonLoading),
    };
  }
}

class _QuestionView extends ConsumerStatefulWidget {
  const _QuestionView({required this.question});

  final AdminQuestion question;

  @override
  ConsumerState<_QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends ConsumerState<_QuestionView> {
  bool _busy = false;
  String? _error;
  List<String> _blockReasons = const [];
  bool _offerDuplicateOverride = false;

  Future<void> _run(QuestionAction action, {bool acknowledgeDuplicates = false}) async {
    final l10n = ObLocalizations.of(context);
    String? comment;
    if (action.needsComment) {
      comment = await showDialog<String>(context: context, builder: (_) => const _CommentDialog());
      if (comment == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _blockReasons = const [];
      _offerDuplicateOverride = false;
    });
    try {
      await ref
          .read(adminQuestionRepositoryProvider)
          .act(widget.question.id, action, comment: comment, acknowledgeDuplicates: acknowledgeDuplicates);
      ref
        ..invalidate(adminQuestionProvider(widget.question.id))
        ..invalidate(adminQuestionsProvider);
    } on Object catch (error) {
      final reasons = blockReasonsOf(error);
      setState(() {
        _error = adminFailureMessage(l10n, error);
        _blockReasons = reasons;
        _offerDuplicateOverride = reasons.contains('DUPLICATE_QUESTION');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(ObLocalizations l10n, QuestionAction action) => switch (action) {
    QuestionAction.submit => l10n.adminActionSubmit,
    QuestionAction.approve => l10n.adminActionApprove,
    QuestionAction.requestChanges => l10n.adminActionRequestChanges,
    QuestionAction.reject => l10n.adminActionReject,
    QuestionAction.publish => l10n.adminActionPublish,
    QuestionAction.archive => l10n.adminActionArchive,
    QuestionAction.restore => l10n.adminActionRestore,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final question = widget.question;
    final actions = questionActionsFor(question);
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
                        child: Text(adminQuestionTypeLabel(l10n, question.type), style: theme.textTheme.headlineSmall),
                      ),
                    ),
                    StatusChip(status: question.workflowStatus),
                  ],
                ),
                Text(
                  [
                    l10n.adminQuestionVersion(question.version),
                    l10n.questionMarks(
                      question.marks == question.marks.roundToDouble() ? question.marks.round() : question.marks,
                    ),
                    if (question.difficulty != null) l10n.questionDifficultyLevel(question.difficulty!),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
                if (question.pendingStatus != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(l10n.adminPendingEdit, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (const {'draft', 'changes_requested', 'published'}.contains(question.workflowStatus))
                      OutlinedButton.icon(
                        key: const Key('edit-question'),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(l10n.adminEditQuestion),
                        onPressed: _busy ? null : () => context.go('/questions/${question.id}/edit'),
                      ),
                    for (final (index, action) in actions.indexed)
                      index == 0
                          ? FilledButton(
                              key: Key('action-${action.name}'),
                              onPressed: _busy ? null : () => _run(action),
                              child: Text(_label(l10n, action)),
                            )
                          : OutlinedButton(
                              key: Key('action-${action.name}'),
                              onPressed: _busy ? null : () => _run(action),
                              child: Text(_label(l10n, action)),
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
                      key: const Key('action-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                  for (final reason in _blockReasons) Text('• ${gateReason(l10n, reason)}'),
                  if (_offerDuplicateOverride)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: OutlinedButton(
                        key: const Key('action-publish-duplicate'),
                        onPressed: _busy ? null : () => _run(QuestionAction.publish, acknowledgeDuplicates: true),
                        child: Text(l10n.adminAcknowledgeDuplicates),
                      ),
                    ),
                ],
                if (question.issues.isNotEmpty) ...[
                  SectionHeader(title: l10n.adminQuestionIssues),
                  for (final issue in question.issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, size: AppSizes.iconSmall, color: theme.colorScheme.error),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(child: Text(issue, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
                    ),
                ],
                SectionHeader(title: l10n.adminColumnStem),
                ContentDocView(
                  blankLabel: ObLocalizations.of(context).contentBlank,
                  doc: question.stem,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
                ),
                if (question.options.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  for (final option in question.options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: _AdminOption(option: option),
                    ),
                ],
                for (final part in question.parts)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Card(
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${part.label} · ${l10n.questionMarks(part.marks.round())}',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: part.prompt),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (question.explanation != null) ...[
                  SectionHeader(title: l10n.questionExplanation),
                  ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: question.explanation!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminOption extends StatelessWidget {
  const _AdminOption({required this.option});

  final AdminOption option;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    return Semantics(
      label: '${option.label}${option.isCorrect ? ', ${l10n.questionOptionCorrectMark}' : ''}',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: option.isCorrect ? semantic.successContainer : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppShapes.medium),
          border: Border.all(color: option.isCorrect ? semantic.success : scheme.outline),
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 14, child: Text(option.label)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: option.content),
            ),
            if (option.isCorrect) Icon(Icons.check_circle, color: semantic.success),
          ],
        ),
      ),
    );
  }
}

/// Reviewer comment / archive reason. Owns its controller so the field outlives the closing animation.
class _CommentDialog extends StatefulWidget {
  const _CommentDialog();

  @override
  State<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends State<_CommentDialog> {
  final _controller = TextEditingController();
  bool _tooShort = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.length >= 3) {
      Navigator.of(context).pop(text); // the server requires 3..500 characters
    } else {
      setState(() => _tooShort = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminReason),
      content: TextField(
        key: const Key('comment-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(
          helperText: l10n.adminReasonHint,
          errorText: _tooShort ? l10n.adminReasonTooShort : null,
        ),
        onChanged: (_) {
          if (_tooShort) setState(() => _tooShort = false);
        },
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(key: const Key('comment-confirm'), onPressed: _confirm, child: Text(l10n.actionContinue)),
      ],
    );
  }
}
