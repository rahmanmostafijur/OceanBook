import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/catalog/admin_catalog_api.dart' show Paged;
import 'package:oceanbook_admin/features/questionbank/admin_question_api.dart';

Map<String, Object?> _doc(String text) => {
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

/// The snapshot the server returns for [fakeAdminQuestion], with an English translation the editor
/// must keep when it saves a Bangla edit.
Map<String, Object?> fakeRawContent({Map<String, Object?>? stem}) => {
  'type': 'mcq_single',
  'source_locale': 'bn',
  'stimulus_id': null,
  'education_level_id': 'l1',
  'subject_id': 's1',
  'chapter_id': 'c1',
  'topic_id': 't1',
  'difficulty': 2,
  'cognitive_level': null,
  'marks': '1.00',
  'answer_spec': <String, Object?>{},
  'access_level': 'free',
  'required_entitlement_key': null,
  'translations': {
    'bn': {'stem': stem ?? _doc('আলোর বেগ কত?'), 'origin': 'original'},
    'en': {'stem': _doc('What is the speed of light?'), 'origin': 'human'},
  },
  'options': [
    {
      'label': 'ক',
      'is_correct': true,
      'content': {'bn': _doc('প্রথম উত্তর'), 'en': _doc('First answer')},
    },
    {
      'label': 'খ',
      'is_correct': false,
      'content': {'bn': _doc('দ্বিতীয় উত্তর')},
    },
  ],
  'parts': <Object?>[],
};

AdminQuestion fakeAdminQuestion({
  String status = 'in_review',
  String? pendingStatus,
  List<String> issues = const [],
  int version = 0,
  Map<String, Object?>? rawContent,
}) => AdminQuestion(
  rawContent: rawContent ?? fakeRawContent(),
  id: 'q1',
  type: QuestionType.mcqSingle,
  status: status,
  pendingStatus: pendingStatus,
  revisionStatus: pendingStatus ?? status,
  version: version,
  latestRevision: version + 1,
  marks: 1,
  difficulty: 2,
  sourceLocale: 'bn',
  stem: _doc('আলোর বেগ কত?'),
  options: [
    AdminOption(label: 'ক', isCorrect: true, content: _doc('প্রথম উত্তর')),
    AdminOption(label: 'খ', isCorrect: false, content: _doc('দ্বিতীয় উত্তর')),
  ],
  parts: const [],
  issues: issues,
);

/// Scripted admin question bank: records calls and can fail workflow actions the way the server does.
class FakeAdminQuestions implements AdminQuestionRepository {
  FakeAdminQuestions({AdminQuestion? question}) : current = question ?? fakeAdminQuestion();

  AdminQuestion current;

  /// When set, the question list returns these rows instead of the single default one.
  List<AdminQuestionRow>? questionRows;
  Object? actionError;
  final List<String> calls = [];
  Object? saveError;

  /// Content of the last create/update, as the editor sent it.
  Map<String, Object?>? savedContent;

  /// Passages by id; `createStimulus` adds `s-new` and records what was sent.
  final Map<String, AdminStimulus> stimuli = {};
  Map<String, Object?>? createdStimulus;

  @override
  Future<AdminStimulus> stimulus(String id) async => stimuli[id]!;

  @override
  Future<AdminStimulus> createStimulus(String sourceLocale, Map<String, Object?> translations) async {
    calls.add('stimulus:$sourceLocale');
    createdStimulus = translations;
    return stimuli['s-new'] = AdminStimulus(id: 's-new', sourceLocale: sourceLocale, translations: translations);
  }

  @override
  Future<Paged<AdminQuestionRow>> questions({
    String? status,
    QuestionType? type,
    bool needsReview = false,
    String? subjectId,
    int page = 1,
    int pageSize = 25,
  }) async {
    calls.add('questions:${status ?? ''}:${type?.wire ?? ''}:$needsReview:$page');
    if (questionRows != null) return Paged(rows: questionRows!, total: questionRows!.length);
    return Paged(
      rows: [
        AdminQuestionRow(
          id: 'q1',
          type: QuestionType.mcqSingle,
          status: current.status,
          pendingStatus: current.pendingStatus,
          version: current.version,
          marks: 1,
          difficulty: 2,
          accessLevel: 'free',
          stem: 'আলোর বেগ কত?',
          updatedAt: DateTime.utc(2026, 10),
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<AdminQuestion> question(String id) async => current;

  @override
  Future<AdminQuestion> createQuestion(Map<String, Object?> content, {String? changeNote}) async {
    if (saveError != null) throw saveError!;
    calls.add('create:${changeNote ?? ''}');
    savedContent = content;
    return current;
  }

  @override
  Future<AdminQuestion> updateQuestion(String id, Map<String, Object?> content, {String? changeNote}) async {
    if (saveError != null) throw saveError!;
    calls.add('update:$id:${changeNote ?? ''}');
    savedContent = content;
    return current;
  }

  @override
  Future<AdminQuestion> act(
    String id,
    QuestionAction action, {
    String? comment,
    bool acknowledgeDuplicates = false,
  }) async {
    calls.add('${action.name}:${comment ?? ''}:$acknowledgeDuplicates');
    if (actionError != null) throw actionError!;
    return current;
  }

  /// The paper the detail, edit and action calls work on, and what the last create/update sent.
  AdminPaper currentPaper = fakePaper();
  Object? paperError;
  Map<String, Object?>? savedPaper;
  List<AdminPaperItem>? savedItems;

  @override
  Future<AdminPaper> paper(String id) async => currentPaper;

  @override
  Future<AdminPaper> createPaper(Map<String, Object?> body) async {
    if (paperError != null) throw paperError!;
    calls.add('paper-create');
    savedPaper = body;
    return currentPaper;
  }

  @override
  Future<AdminPaper> updatePaper(String id, Map<String, Object?> patch) async {
    if (paperError != null) throw paperError!;
    calls.add('paper-update:$id');
    savedPaper = patch;
    return currentPaper;
  }

  @override
  Future<List<AdminPaperItem>> setPaperItems(String id, List<AdminPaperItem> items) async {
    if (paperError != null) throw paperError!;
    calls.add('paper-items:$id');
    savedItems = items;
    return items;
  }

  @override
  Future<AdminPaper> publishPaper(String id) async {
    if (paperError != null) throw paperError!;
    calls.add('paper-publish:$id');
    return currentPaper;
  }

  @override
  Future<AdminPaper> archivePaper(String id, String reason) async {
    if (paperError != null) throw paperError!;
    calls.add('paper-archive:$id:$reason');
    return currentPaper;
  }

  @override
  Future<Paged<AdminPaper>> papers({String? status, int page = 1, int pageSize = 25}) async {
    calls.add('papers:${status ?? ''}:$page');
    return const Paged(
      rows: [
        AdminPaper(
          id: 'p1',
          examYear: 2022,
          examKind: 'board_final',
          section: 'mcq',
          status: 'published',
          boardCount: 1,
          itemCount: 30,
        ),
      ],
      total: 1,
    );
  }
}

/// A creative question (stimulus `s1` plus parts ক and খ) as the server returns it.
AdminQuestion fakeCreativeQuestion({String status = 'draft'}) {
  final raw = {
    ...fakeRawContent(),
    'type': 'creative',
    'stimulus_id': 's1',
    'marks': '3.00',
    'options': <Object?>[],
    'parts': [
      {
        'label': 'ক',
        'cognitive_level': 'knowledge',
        'marks': '1.00',
        'prompt': {'bn': _doc('প্রথম অংশ'), 'en': _doc('First part')},
        'model_answer': {'bn': _doc('উত্তর')},
      },
      {
        'label': 'খ',
        'cognitive_level': 'comprehension',
        'marks': '2.00',
        'prompt': {'bn': _doc('দ্বিতীয় অংশ')},
      },
    ],
  };
  return AdminQuestion(
    rawContent: raw,
    id: 'q1',
    type: QuestionType.creative,
    status: status,
    revisionStatus: status,
    version: 0,
    latestRevision: 1,
    marks: 3,
    sourceLocale: 'bn',
    stimulusId: 's1',
    stem: _doc('উদ্দীপক পড়ে উত্তর দাও'),
    options: const [],
    parts: const [],
    issues: const [],
  );
}

AdminStimulus fakeStimulus() => AdminStimulus(
  id: 's1',
  sourceLocale: 'bn',
  translations: {'bn': _doc('একটি উদ্দীপক'), 'en': _doc('A passage')},
);

AdminStimulus fakeStimulusWithImage() => const AdminStimulus(
  id: 's1',
  sourceLocale: 'bn',
  translations: {
    'bn': {
      'type': 'doc',
      'v': 1,
      'blocks': [
        {'type': 'image', 'asset_id': 'a1', 'alt': 'diagram'},
      ],
    },
  },
);

/// A draft HSC Physics paper holding one question, as the server returns it.
AdminPaper fakePaper({String status = 'draft', List<AdminPaperItem>? items}) => AdminPaper(
  id: 'p1',
  examYear: 2022,
  examKind: 'board_final',
  section: 'mcq',
  status: status,
  boardCount: 1,
  itemCount: (items ?? const [AdminPaperItem(questionId: 'q1', itemNumber: '1')]).length,
  educationLevelId: 'l1',
  subjectId: 's1',
  boardIds: const ['b1'],
  totalMarks: 30,
  items: items ?? const [AdminPaperItem(questionId: 'q1', itemNumber: '1')],
);
