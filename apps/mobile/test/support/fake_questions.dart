import 'package:ob_core/ob_core.dart';

const sscLevel = EducationLevelRef(id: 'lvl-ssc', key: 'ssc', name: 'এসএসসি');
const hscLevel = EducationLevelRef(id: 'lvl-hsc', key: 'hsc', name: 'এইচএসসি');
const physics = SubjectRef(id: 'sub-phy', familyKey: 'physics', name: 'পদার্থবিজ্ঞান ১ম পত্র', paperNumber: 1);
const chemistry = SubjectRef(id: 'sub-chem', familyKey: 'chemistry', name: 'রসায়ন ১ম পত্র', paperNumber: 1);

Map<String, Object?> docOf(String text) => {
  'type': 'doc',
  'v': 1,
  'blocks': [
    {
      'type': 'paragraph',
      'inlines': [
        {'type': 'text', 'text': text},
      ],
    },
  ],
};

QuestionCard fakeQuestionCard(
  int i, {
  AccessLevel access = AccessLevel.free,
  QuestionType type = QuestionType.mcqSingle,
}) => QuestionCard(
  id: 'q-$i',
  type: type,
  locale: 'bn',
  stemText: 'প্রশ্ন নম্বর $i',
  marks: 1,
  difficulty: 2,
  accessLevel: access,
  availableLocales: const ['bn'],
);

QuestionDetail fakeQuestionDetail({
  bool canViewAnswers = true,
  List<String> reasons = const [],
  bool creative = false,
}) {
  final options = [
    for (final (i, label) in ['ক', 'খ', 'গ', 'ঘ'].indexed)
      QuestionOption(
        id: 'o-$i',
        label: label,
        content: docOf('উত্তর $label'),
        isCorrect: canViewAnswers ? i == 1 : null,
      ),
  ];
  return QuestionDetail(
    card: fakeQuestionCard(
      1,
      access: canViewAnswers ? AccessLevel.free : AccessLevel.registered,
      type: creative ? QuestionType.creative : QuestionType.mcqSingle,
    ),
    stem: docOf('আলোর বেগ কত?'),
    stimulus: creative ? docOf('একটি বস্তু ১০ মি/সে বেগে চলছে।') : null,
    options: creative ? const [] : options,
    parts: creative
        ? [
            QuestionPart(
              label: 'ক',
              cognitiveLevel: 'knowledge',
              marks: 1,
              prompt: docOf('বেগ কাকে বলে?'),
              modelAnswer: canViewAnswers ? docOf('সরণের পরিবর্তনের হার') : null,
            ),
          ]
        : const [],
    appearances: const [QuestionAppearance(examYear: 2022, examKind: 'board_final', itemNumber: '12')],
    access: QuestionAccess(level: AccessLevel.registered, canViewAnswers: canViewAnswers, reasons: reasons),
    explanation: canViewAnswers ? docOf('আলোর বেগ ৩ লক্ষ কিমি/সে') : null,
  );
}

/// In-memory question bank that records the queries it receives (filtering is the server's job).
class FakeQuestions implements QuestionRepository {
  FakeQuestions({this.total = 3, QuestionDetail? detail}) : detail = detail ?? fakeQuestionDetail();

  final int total;
  QuestionDetail detail;
  final List<(QuestionQuery, String?)> queries = [];
  final List<String> chapterRequests = [];

  @override
  Future<List<EducationLevelRef>> levels() async => const [sscLevel, hscLevel];

  @override
  Future<List<BoardRef>> boards() async => const [BoardRef(id: 'brd-dhaka', key: 'dhaka', name: 'ঢাকা')];

  @override
  Future<List<SubjectRef>> subjects({String? levelId}) async => const [physics, chemistry];

  @override
  Future<List<ChapterRef>> chapters(String subjectId) async {
    chapterRequests.add(subjectId);
    return const [ChapterRef(id: 'ch-1', number: 1, name: 'ভৌত জগৎ')];
  }

  @override
  Future<CursorPage<QuestionCard>> questions(QuestionQuery query, {String? cursor, int limit = 20}) async {
    queries.add((query, cursor));
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, total);
    return CursorPage(
      items: [for (var i = start; i < end; i++) fakeQuestionCard(i)],
      nextCursor: end < total ? '$end' : null,
    );
  }

  @override
  Future<QuestionDetail> question(String id) async => detail;
}
