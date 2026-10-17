import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

String questionTypeLabel(ObLocalizations l10n, QuestionType type) => switch (type) {
  QuestionType.mcqSingle => l10n.questionTypeMcqSingle,
  QuestionType.mcqMulti => l10n.questionTypeMcqMulti,
  QuestionType.trueFalse => l10n.questionTypeTrueFalse,
  QuestionType.shortAnswer => l10n.questionTypeShortAnswer,
  QuestionType.creative => l10n.questionTypeCreative,
  QuestionType.fillBlank => l10n.questionTypeFillBlank,
  QuestionType.matching => l10n.questionTypeMatching,
  QuestionType.unknown => '',
};

/// Subjects are board papers; show the family name once and the paper number as a suffix is already in
/// the localized label, so the label is used as-is.
String subjectLabel(SubjectRef subject) => subject.name;
