import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../academics/admin_curriculum_api.dart';

/// Level, subject, chapter and topic pickers of the question editor. Level and subject are required;
/// the lists narrow as the choices above them are made.
class QuestionClassification extends StatelessWidget {
  const QuestionClassification({
    required this.levels,
    required this.subjects,
    required this.chapters,
    required this.levelId,
    required this.subjectId,
    required this.chapterId,
    required this.topicId,
    required this.onLevel,
    required this.onSubject,
    required this.onChapter,
    required this.onTopic,
    super.key,
  });

  final List<CurriculumOption> levels;
  final List<CurriculumSubject> subjects;
  final List<CurriculumChapter> chapters;
  final String? levelId;
  final String? subjectId;
  final String? chapterId;
  final String? topicId;
  final ValueChanged<String?> onLevel;
  final ValueChanged<String?> onSubject;
  final ValueChanged<String?> onChapter;
  final ValueChanged<String?> onTopic;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final levelSubjects = subjects.where((s) => s.educationLevelId == levelId).toList();
    final topics = chapters.where((c) => c.id == chapterId).expand((c) => c.topics).where((t) => t.isActive);
    DropdownButtonFormField<String?> picker(
      String key,
      String label,
      String? value,
      List<(String, String)> items,
      ValueChanged<String?> onChanged, {
      bool requiredValue = false,
    }) => DropdownButtonFormField<String?>(
      key: Key(key),
      initialValue: items.any((e) => e.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (!requiredValue) DropdownMenuItem(value: null, child: Text(l10n.adminNoneOption)),
        for (final (id, name) in items) DropdownMenuItem(value: id, child: Text(name)),
      ],
      onChanged: onChanged,
      validator: requiredValue ? (v) => v == null ? l10n.errorValidation : null : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        picker(
          'question-level',
          l10n.adminLevel,
          levelId,
          [
            for (final l in levels) (l.id, l.name.resolve(locale)),
          ],
          onLevel,
          requiredValue: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        picker(
          'question-subject',
          l10n.adminFieldSubject,
          subjectId,
          [
            for (final s in levelSubjects) (s.id, s.name.resolve(locale)),
          ],
          onSubject,
          requiredValue: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        picker('question-chapter', l10n.adminFieldChapter, chapterId, [
          for (final c in chapters.where((c) => c.isActive)) (c.id, '${c.number}. ${c.name.resolve(locale)}'),
        ], onChapter),
        const SizedBox(height: AppSpacing.sm),
        picker('question-topic', l10n.adminFieldTopic, topicId, [
          for (final t in topics) (t.id, t.name.resolve(locale)),
        ], onTopic),
      ],
    );
  }
}
