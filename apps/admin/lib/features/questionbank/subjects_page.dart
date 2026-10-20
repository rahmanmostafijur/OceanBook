import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../academics/admin_curriculum_api.dart';
import '../academics/name_dialog.dart';
import 'admin_question_api.dart';

final adminSubjectsProvider = FutureProvider.autoDispose<List<AdminSubject>>(
  (ref) => ref.watch(adminQuestionRepositoryProvider).subjects(),
);

final _chaptersProvider = FutureProvider.autoDispose.family<List<CurriculumChapter>, String>(
  (ref, subjectId) => ref.watch(adminCurriculumRepositoryProvider).chapters(subjectId),
);

/// The curriculum tree: subjects (a board paper is its own subject, grouped by family), each with its
/// chapters and topics. Chapters load when a subject is opened and can be added, renamed and archived.
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
      _ => PageLoading(semanticLabel: l10n.commonLoading),
    };
  }
}

class _SubjectTile extends ConsumerWidget {
  const _SubjectTile({required this.subject});

  final AdminSubject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = ObLocalizations.of(context);
    final repo = ref.read(adminCurriculumRepositoryProvider);
    final provider = _chaptersProvider(subject.id);
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
            builder: (context, ref, _) => switch (ref.watch(provider)) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (value.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(l10n.adminNoChapters),
                    ),
                  for (final chapter in value)
                    _ChapterTile(chapter: chapter, onChanged: () => ref.invalidate(provider)),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: TextButton.icon(
                      key: Key('add-chapter-${subject.id}'),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.adminAddChapter),
                      onPressed: () => showNameDialog(
                        context,
                        title: l10n.adminAddChapter,
                        askNumber: true,
                        initialNumber: value.fold(0, (max, c) => c.number > max ? c.number : max) + 1,
                        onSave: (name, number) async {
                          await repo.createChapter(subject.id, number: number!, name: name);
                          ref.invalidate(provider);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              AsyncError(:final error) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(adminFailureMessage(l10n, error)),
              ),
              _ => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: PageLoading.linear(semanticLabel: l10n.commonLoading),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _ChapterTile extends ConsumerWidget {
  const _ChapterTile({required this.chapter, required this.onChanged});

  final CurriculumChapter chapter;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final repo = ref.read(adminCurriculumRepositoryProvider);

    Future<void> toggle(Future<void> Function() action) async {
      try {
        await action();
        onChanged();
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(adminFailureMessage(l10n, error))));
        }
      }
    }

    Widget actions({
      required Key editKey,
      required String editLabel,
      required VoidCallback onEdit,
      required Key toggleKey,
      required bool isActive,
      required VoidCallback onToggle,
    }) => Wrap(
      children: [
        IconButton(key: editKey, tooltip: editLabel, icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
        IconButton(
          key: toggleKey,
          tooltip: isActive ? l10n.adminArchiveItem : l10n.adminRestoreItem,
          icon: Icon(isActive ? Icons.archive_outlined : Icons.unarchive_outlined),
          onPressed: onToggle,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          title: Text('${chapter.number}. ${chapter.name.resolve(locale)}'),
          subtitle: chapter.isActive ? null : Text(l10n.adminStatusArchived),
          trailing: actions(
            editKey: Key('edit-chapter-${chapter.id}'),
            editLabel: l10n.adminEditChapter,
            onEdit: () => showNameDialog(
              context,
              title: l10n.adminEditChapter,
              askNumber: true,
              initial: chapter.name,
              initialNumber: chapter.number,
              onSave: (name, number) async {
                await repo.updateChapter(chapter.id, name: name, number: number);
                onChanged();
              },
            ),
            toggleKey: Key('toggle-chapter-${chapter.id}'),
            isActive: chapter.isActive,
            onToggle: () => toggle(() => repo.updateChapter(chapter.id, isActive: !chapter.isActive)),
          ),
        ),
        for (final topic in chapter.topics)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsetsDirectional.only(start: AppSpacing.xxl, end: AppSpacing.md),
            title: Text(topic.name.resolve(locale)),
            subtitle: topic.isActive ? null : Text(l10n.adminStatusArchived, style: theme.textTheme.bodySmall),
            trailing: actions(
              editKey: Key('edit-topic-${topic.id}'),
              editLabel: l10n.adminEditTopic,
              onEdit: () => showNameDialog(
                context,
                title: l10n.adminEditTopic,
                initial: topic.name,
                onSave: (name, _) async {
                  await repo.updateTopic(topic.id, name: name);
                  onChanged();
                },
              ),
              toggleKey: Key('toggle-topic-${topic.id}'),
              isActive: topic.isActive,
              onToggle: () => toggle(() => repo.updateTopic(topic.id, isActive: !topic.isActive)),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.xl),
          child: TextButton.icon(
            key: Key('add-topic-${chapter.id}'),
            icon: const Icon(Icons.add),
            label: Text(l10n.adminAddTopic),
            onPressed: () => showNameDialog(
              context,
              title: l10n.adminAddTopic,
              onSave: (name, _) async {
                await repo.createTopic(chapter.id, name: name);
                onChanged();
              },
            ),
          ),
        ),
      ],
    );
  }
}
