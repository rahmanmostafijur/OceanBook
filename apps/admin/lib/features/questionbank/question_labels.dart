import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

String adminQuestionTypeLabel(ObLocalizations l10n, QuestionType type) => switch (type) {
  QuestionType.mcqSingle => l10n.questionTypeMcqSingle,
  QuestionType.mcqMulti => l10n.questionTypeMcqMulti,
  QuestionType.trueFalse => l10n.questionTypeTrueFalse,
  QuestionType.shortAnswer => l10n.questionTypeShortAnswer,
  QuestionType.creative => l10n.questionTypeCreative,
  QuestionType.fillBlank => l10n.questionTypeFillBlank,
  QuestionType.matching => l10n.questionTypeMatching,
  QuestionType.unknown => '',
};

String examKindLabel(ObLocalizations l10n, String kind) => switch (kind) {
  'board_final' => l10n.adminExamBoardFinal,
  'test' => l10n.adminExamTest,
  'pre_test' => l10n.adminExamPreTest,
  'model' => l10n.adminExamModel,
  'admission' => l10n.adminExamAdmission,
  _ => kind,
};
