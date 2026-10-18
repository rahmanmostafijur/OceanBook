import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_question_api.dart';

final adminSubjectsProvider = FutureProvider.autoDispose<List<AdminSubject>>(
  (ref) => ref.watch(adminQuestionRepositoryProvider).subjects(),
);

final _chaptersProvider = FutureProvider.autoDispose.family<List<ChapterRef>, String>(
  (ref, subjectId) => ref.watch(adminQuestionRepositoryProvider).chapters(subjectId),
);

/// The curriculum tree: subjects (a board paper is its own subject, grouped by family), each with its
/// chapters and topics. Chapters load when a subject is opened.
class SubjectsPage extends ConsumerWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    return switch (ref.watch(adminSubjectsProvider)) {
      AsyncData(:final value) when value.isEmpty => EmptyState(
        icon: Icons.library_books_outlined,
        title: l10n.adminNoSubjects,
      ),
      AsyncData(:final value) => ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          for (final subject in value) _SubjectTile(subject: subject),
        ],
      ),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminSubjectsProvider),
      ),
      _ => PageLoading(semanticLabel: ObLocalizations.of(context).commonLoading),
    };
  }
}

class _SubjectTile extends ConsumerWidget {
  const _SubjectTile({required this.subject});

  final AdminSubject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ExpansionTile(
        expansionAnimationStyle: AppMotion.reduced(context) ? AnimationStyle.noAnimation : null,
        key: Key('subject-${subject.id}'),
        title: Text(subject.name),
        subtitle: Text(
          [subject.familyKey, ?subject.boardCode].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Consumer(
            builder: (context, ref, _) => switch (ref.watch(_chaptersProvider(subject.id))) {
              AsyncData(:final value) => Column(
                children: [
                  for (final chapter in value)
                    ListTile(
                      dense: true,
                      title: Text('${chapter.number}. ${chapter.name}'),
                      subtitle: chapter.topics.isEmpty
                          ? null
                          : Text(chapter.topics.map((t) => t.name).join(' · '), style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
              AsyncError(:final error) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(adminFailureMessage(ObLocalizations.of(context), error)),
              ),
              _ => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: PageLoading.linear(semanticLabel: ObLocalizations.of(context).commonLoading),
              ),
            },
          ),
        ],
      ),
    );
  }
}
