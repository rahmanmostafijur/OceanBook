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

  late List<CurriculumChapter> chaptersList;
  Object? writeError;
  final List<String> calls = [];

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
