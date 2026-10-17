import '../api/api_client.dart';
import '../api/api_models.dart';
import '../catalog/catalog_models.dart' show CursorPage;
import 'question_models.dart';

/// Read-only question-bank access for apps. Implementations must not filter or decide access locally:
/// whether answers are visible is the server's decision, carried in `QuestionDetail.access`.
abstract interface class QuestionRepository {
  Future<List<EducationLevelRef>> levels();
  Future<List<BoardRef>> boards();
  Future<List<SubjectRef>> subjects({String? levelId});
  Future<List<ChapterRef>> chapters(String subjectId);
  Future<CursorPage<QuestionCard>> questions(QuestionQuery query, {String? cursor, int limit = 20});
  Future<QuestionDetail> question(String id);
}

class QuestionApi implements QuestionRepository {
  QuestionApi(this.api, {this.locale = 'bn'});

  final ApiClient api;

  /// Language used for taxonomy labels (questions themselves follow `Accept-Language`).
  final String locale;

  Future<List<T>> _list<T>(String path, T Function(Map<String, Object?>) decode, {Map<String, Object?>? query}) async {
    final response = await api.get(
      path,
      query: query,
      decode: (json) => [for (final item in json! as List) decode(item as Map<String, Object?>)],
    );
    return response.data;
  }

  @override
  Future<List<EducationLevelRef>> levels() => _list('/academics/levels', (j) => EducationLevelRef.fromJson(j, locale));

  @override
  Future<List<BoardRef>> boards() => _list('/academics/boards', (j) => BoardRef.fromJson(j, locale));

  @override
  Future<List<SubjectRef>> subjects({String? levelId}) =>
      _list('/academics/subjects', (j) => SubjectRef.fromJson(j, locale), query: {'education_level_id': levelId});

  @override
  Future<List<ChapterRef>> chapters(String subjectId) => _list(
    '/academics/subjects/${Uri.encodeComponent(subjectId)}/chapters',
    (j) => ChapterRef.fromJson(j, locale),
  );

  @override
  Future<CursorPage<QuestionCard>> questions(QuestionQuery query, {String? cursor, int limit = 20}) async {
    final response = await api.get(
      '/questions',
      query: {...query.toQuery(), 'cursor': cursor, 'limit': limit},
      decode: (json) => [for (final item in json! as List) QuestionCard.fromJson(item as Map<String, Object?>)],
    );
    final page = response.page;
    return CursorPage(items: response.data, nextCursor: page is CursorPageMeta ? page.nextCursor : null);
  }

  @override
  Future<QuestionDetail> question(String id) async {
    final response = await api.get(
      '/questions/${Uri.encodeComponent(id)}',
      decode: (json) => QuestionDetail.fromJson(json! as Map<String, Object?>),
    );
    return response.data;
  }
}
