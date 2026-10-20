import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/features/academics/admin_curriculum_api.dart';

/// In-memory chapters and topics; records writes and can fail them the way the server does.
class FakeAdminCurriculum implements AdminCurriculumRepository {
  FakeAdminCurriculum() {
    chaptersList = [
      const CurriculumChapter(
        id: 'c1',
        number: 1,
        name: LocalizedText({'bn': 'ভৌত জগৎ', 'en': 'Physical world'}),
        isActive: true,
        topics: [
          CurriculumTopic(id: 't1', name: LocalizedText({'bn': 'পরিমাপ', 'en': 'Measurement'}), isActive: true),
        ],
      ),
    ];
  }

  static const hscLevel = CurriculumOption(
    id: 'l1',
    key: 'hsc',
    name: LocalizedText({'bn': 'এইচএসসি', 'en': 'HSC'}),
  );
  static const scienceGroup = CurriculumOption(
    id: 'g1',
    key: 'science',
    name: LocalizedText({'bn': 'বিজ্ঞান', 'en': 'Science'}),
  );

  List<CurriculumSubject> subjectsList = const [
    CurriculumSubject(
      id: 's1',
      curriculumId: 'cur1',
      educationLevelId: 'l1',
      slug: 'physics-1st',
      familyKey: 'physics',
      boardCode: '174',
      paperNumber: 1,
      name: LocalizedText({'bn': 'পদার্থবিজ্ঞান ১ম পত্র', 'en': 'Physics 1st Paper'}),
      isActive: true,
      groups: [SubjectGroupLink(groupId: 'g1', offering: 'compulsory')],
    ),
  ];
  late List<CurriculumChapter> chaptersList;
  Object? writeError;
  final List<String> calls = [];

  @override
  Future<List<CurriculumSubject>> subjects() async => subjectsList;

  @override
  Future<List<CurriculumOption>> levels() async => const [hscLevel];

  @override
  Future<List<CurriculumOption>> curricula() async => const [
    CurriculumOption(id: 'cur1', key: 'nctb_2012', name: LocalizedText({'bn': 'এনসিটিবি ২০১২', 'en': 'NCTB 2012'})),
  ];

  @override
  Future<List<CurriculumOption>> groups(String levelId) async => const [scienceGroup];

  @override
  Future<void> createSubject({
    required String curriculumId,
    required String levelId,
    required String slug,
    required SubjectFields fields,
  }) async {
    _check();
    calls.add(
      'createSubject:$curriculumId:$levelId:$slug:${fields.familyKey}:${fields.name.values}:${fields.boardCode}:${fields.paperNumber}:${fields.groups.map((g) => "${g.groupId}=${g.offering}")}',
    );
  }

  @override
  Future<void> updateSubject(String id, {SubjectFields? fields, bool? isActive}) async {
    _check();
    calls.add('updateSubject:$id:${fields?.familyKey}:${fields?.name.values}:${fields?.paperNumber}:$isActive');
  }

  @override
  Future<List<CurriculumChapter>> chapters(String subjectId) async => chaptersList;

  void _check() {
    if (writeError != null) throw writeError!;
  }

  @override
  Future<void> createChapter(String subjectId, {required int number, required LocalizedText name}) async {
    _check();
    calls.add('createChapter:$subjectId:$number:${name.values}');
  }

  @override
  Future<void> updateChapter(String id, {int? number, LocalizedText? name, bool? isActive}) async {
    _check();
    calls.add('updateChapter:$id:$number:${name?.values}:$isActive');
  }

  @override
  Future<void> createTopic(String chapterId, {required LocalizedText name}) async {
    _check();
    calls.add('createTopic:$chapterId:${name.values}');
  }

  @override
  Future<void> updateTopic(String id, {LocalizedText? name, bool? isActive}) async {
    _check();
    calls.add('updateTopic:$id:${name?.values}:$isActive');
  }
}
