import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../data/question_providers.dart';
import 'question_labels.dart';

/// One question: passage, stem, options or parts. Answers and explanations are shown only when the
/// server sent them (`access.canViewAnswers`); otherwise the screen explains why they are locked.
class QuestionScreen extends ConsumerWidget {
  const QuestionScreen({required this.questionId, super.key});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final detail = ref.watch(questionDetailProvider(questionId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionDetailTitle)),
      body: switch (detail) {
        AsyncData(:final value) => _QuestionBody(detail: value),
        AsyncError(:final error) => ErrorState(
          title: l10n.errorTitle,
          message: failureMessage(l10n, error),
          retryLabel: l10n.actionRetry,
          onRetry: () => ref.invalidate(questionDetailProvider(questionId)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _QuestionBody extends StatefulWidget {
  const _QuestionBody({required this.detail});

  final QuestionDetail detail;

  @override
  State<_QuestionBody> createState() => _QuestionBodyState();
}

class _QuestionBodyState extends State<_QuestionBody> {
  bool _revealed = false;
  final _picked = <String>{};

  QuestionDetail get _detail => widget.detail;

  bool get _multi => _detail.card.type == QuestionType.mcqMulti;

  void _pick(String id) => setState(() {
    if (_multi) {
      _picked.contains(id) ? _picked.remove(id) : _picked.add(id);
    } else {
      _picked
        ..clear()
        ..add(id);
    }
  });

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final gutter = AppSpacing.gutter(MediaQuery.sizeOf(context).width);
    final card = _detail.card;
    final marks = card.marks == card.marks.roundToDouble() ? card.marks.round() : card.marks;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.sectionGap),
      children: [
        ConstrainedContent(
          maxWidth: AppSizes.maxReadableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  Chip(label: Text(questionTypeLabel(l10n, card.type))),
                  Chip(label: Text(l10n.questionMarks(marks))),
                  if (card.difficulty != null) Chip(label: Text(l10n.questionDifficultyLevel(card.difficulty!))),
                ],
              ),
              if (_detail.stimulus != null) ...[
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: AppSpacing.cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(l10n.questionStimulus, style: theme.textTheme.titleSmall),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: _detail.stimulus!),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ContentDocView(
                blankLabel: ObLocalizations.of(context).contentBlank,
                doc: _detail.stem,
                style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
              ),
              if (_detail.options.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final option in _detail.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _OptionTile(
                      option: option,
                      picked: _picked.contains(option.id),
                      revealed: _revealed,
                      onTap: () => _pick(option.id),
                    ),
                  ),
              ],
              if (_detail.parts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                for (final part in _detail.parts) _PartTile(part: part, revealed: _revealed, marks: part.marks),
              ],
              const SizedBox(height: AppSpacing.md),
              _AnswerArea(
                detail: _detail,
                revealed: _revealed,
                onToggle: () => setState(() => _revealed = !_revealed),
              ),
              if (_detail.appearances.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.questionAppearedIn(
                    _detail.appearances.map((a) => '${a.examYear} · #${a.itemNumber}').join(', '),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.option, required this.picked, required this.revealed, required this.onTap});

  final QuestionOption option;
  final bool picked;
  final bool revealed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final correct = revealed && option.isCorrect == true;
    final wrongPick = revealed && picked && option.isCorrect == false;
    final background = correct
        ? AppSemanticColors.of(context).successContainer
        : picked
        ? scheme.secondaryContainer
        : scheme.surfaceContainerLow;
    final markColor = correct ? AppSemanticColors.of(context).success : (wrongPick ? scheme.error : null);
    return Semantics(
      button: true,
      selected: picked,
      label:
          '${option.label}. ${_plain(option.content)}${correct ? ', ${l10n.questionOptionCorrectMark}' : ''}${wrongPick ? ', ${l10n.questionOptionWrongMark}' : ''}',
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.medium),
          side: BorderSide(color: markColor ?? scheme.outline, width: markColor == null ? 1 : 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppShapes.medium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: picked ? scheme.primary : scheme.surfaceContainerHighest,
                  foregroundColor: picked ? scheme.onPrimary : scheme.onSurface,
                  child: Text(option.label),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: option.content),
                ),
                if (correct) Icon(Icons.check_circle, color: markColor),
                if (wrongPick) Icon(Icons.cancel, color: markColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _plain(Map<String, Object?> doc) {
    final buffer = StringBuffer();
    for (final block in (doc['blocks'] as List?) ?? const []) {
      for (final inline in ((block as Map)['inlines'] as List?) ?? const []) {
        final node = inline as Map;
        buffer.write(node['text'] ?? node['tex'] ?? '');
      }
    }
    return buffer.toString();
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({required this.part, required this.revealed, required this.marks});

  final QuestionPart part;
  final bool revealed;
  final double marks;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final shownMarks = marks == marks.roundToDouble() ? marks.round() : marks;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${part.label}.', style: theme.textTheme.titleMedium),
                  const SizedBox(width: AppSpacing.xs),
                  Text(l10n.questionMarks(shownMarks), style: theme.textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: part.prompt),
              if (revealed && part.modelAnswer != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.questionModelAnswer, style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xxs),
                ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: part.modelAnswer!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The reveal button, or why answers are locked. The decision is the server's.
class _AnswerArea extends StatelessWidget {
  const _AnswerArea({required this.detail, required this.revealed, required this.onToggle});

  final QuestionDetail detail;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final access = detail.access;
    if (!access.canViewAnswers) {
      final needsSignIn = access.reasons.contains(AccessReason.signInRequired);
      final message = needsSignIn ? l10n.questionAnswerSignIn : l10n.questionAnswerPremium;
      return Card(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            children: [
              Icon(Icons.lock_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(message, style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSecondaryContainer)),
              ),
              if (needsSignIn)
                TextButton(
                  onPressed: () =>
                      context.go('/sign-in?from=${Uri.encodeComponent('/study/questions/${detail.card.id}')}'),
                  child: Text(l10n.actionSignIn),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonalIcon(
          onPressed: onToggle,
          icon: Icon(revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          label: Text(revealed ? l10n.questionHideAnswer : l10n.questionShowAnswer),
        ),
        if (revealed) ...[
          if (detail.modelAnswer != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.questionModelAnswer, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
            ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: detail.modelAnswer!),
          ],
          if (detail.explanation != null) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(l10n.questionExplanation, style: theme.textTheme.titleSmall),
            ),
            const SizedBox(height: AppSpacing.xxs),
            ContentDocView(blankLabel: ObLocalizations.of(context).contentBlank, doc: detail.explanation!),
          ],
        ],
      ],
    );
  }
}
