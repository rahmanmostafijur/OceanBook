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

AdminQuestion fakeAdminQuestion({
  String status = 'in_review',
  String? pendingStatus,
  List<String> issues = const [],
  int version = 0,
}) => AdminQuestion(
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
  Object? actionError;
  final List<String> calls = [];

  @override
  Future<Paged<AdminQuestionRow>> questions({
    String? status,
    QuestionType? type,
    bool needsReview = false,
    int page = 1,
    int pageSize = 25,
  }) async {
    calls.add('questions:${status ?? ''}:${type?.wire ?? ''}:$needsReview:$page');
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
