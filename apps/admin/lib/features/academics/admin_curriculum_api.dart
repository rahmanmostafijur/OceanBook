import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../core/providers.dart';

/// A topic with every locale of its name (the question-bank view resolves to one locale; editing needs all).
@immutable
class CurriculumTopic {
  const CurriculumTopic({required this.id, required this.name, required this.isActive});

  factory CurriculumTopic.fromJson(Map<String, Object?> json) => CurriculumTopic(
    id: json['id']! as String,
    name: LocalizedText.fromJson(json['name']),
    isActive: json['is_active'] as bool? ?? true,
  );

  final String id;
  final LocalizedText name;
  final bool isActive;
}

@immutable
class CurriculumChapter {
  const CurriculumChapter({
    required this.id,
    required this.number,
    required this.name,
    required this.isActive,
    required this.topics,
  });

  factory CurriculumChapter.fromJson(Map<String, Object?> json) => CurriculumChapter(
    id: json['id']! as String,
    number: (json['number']! as num).toInt(),
    name: LocalizedText.fromJson(json['name']),
    isActive: json['is_active'] as bool? ?? true,
    topics: [
      for (final t in (json['topics'] as List? ?? const <Object?>[]))
        CurriculumTopic.fromJson(t! as Map<String, Object?>),
    ],
  );

  final String id;
  final int number;
  final LocalizedText name;
  final bool isActive;
  final List<CurriculumTopic> topics;
}

/// Admin writes for chapters and topics (`/admin/academics`). The server enforces `academics.manage`.
abstract interface class AdminCurriculumRepository {
  Future<List<CurriculumChapter>> chapters(String subjectId);
  Future<void> createChapter(String subjectId, {required int number, required LocalizedText name});
  Future<void> updateChapter(String id, {int? number, LocalizedText? name, bool? isActive});
  Future<void> createTopic(String chapterId, {required LocalizedText name});
  Future<void> updateTopic(String id, {LocalizedText? name, bool? isActive});
}

class AdminCurriculumApi implements AdminCurriculumRepository {
  AdminCurriculumApi(this.api);

  final ApiClient api;

  static Object? _ignore(Object? json) => null;

  @override
  Future<List<CurriculumChapter>> chapters(String subjectId) async => (await api.get(
    '/admin/academics/subjects/$subjectId/chapters',
    decode: (j) => [for (final c in j! as List) CurriculumChapter.fromJson(c as Map<String, Object?>)],
  )).data;

  @override
  Future<void> createChapter(String subjectId, {required int number, required LocalizedText name}) async {
    await api.post(
      '/admin/academics/chapters',
      body: {'subject_id': subjectId, 'number': number, 'name': name.values},
      decode: _ignore,
    );
  }

  @override
  Future<void> updateChapter(String id, {int? number, LocalizedText? name, bool? isActive}) async {
    await api.patch(
      '/admin/academics/chapters/$id',
      body: {'number': ?number, 'name': ?name?.values, 'is_active': ?isActive},
      decode: _ignore,
    );
  }

  @override
  Future<void> createTopic(String chapterId, {required LocalizedText name}) async {
    await api.post(
      '/admin/academics/topics',
      body: {'chapter_id': chapterId, 'name': name.values},
      decode: _ignore,
    );
  }

  @override
  Future<void> updateTopic(String id, {LocalizedText? name, bool? isActive}) async {
    await api.patch(
      '/admin/academics/topics/$id',
      body: {'name': ?name?.values, 'is_active': ?isActive},
      decode: _ignore,
    );
  }
}

final adminCurriculumRepositoryProvider = Provider<AdminCurriculumRepository>(
  (ref) => AdminCurriculumApi(ref.watch(adminApiProvider)),
);
