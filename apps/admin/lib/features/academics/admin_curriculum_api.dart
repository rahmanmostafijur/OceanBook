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

/// A level, curriculum or group a subject can belong to.
@immutable
class CurriculumOption {
  const CurriculumOption({required this.id, required this.key, required this.name});

  factory CurriculumOption.fromJson(Map<String, Object?> json) => CurriculumOption(
    id: json['id']! as String,
    key: json['key']! as String,
    name: LocalizedText.fromJson(json['name']),
  );

  final String id;
  final String key;
  final LocalizedText name;
}

const offerings = ['compulsory', 'elective', 'optional'];

@immutable
class SubjectGroupLink {
  const SubjectGroupLink({required this.groupId, required this.offering});

  final String groupId;
  final String offering;

  Map<String, Object?> toJson() => {'group_id': groupId, 'offering': offering};
}

/// A subject as the curriculum tree shows and edits it.
@immutable
class CurriculumSubject {
  const CurriculumSubject({
    required this.id,
    required this.curriculumId,
    required this.educationLevelId,
    required this.slug,
    required this.familyKey,
    required this.name,
    required this.isActive,
    this.boardCode,
    this.paperNumber,
    this.groups = const [],
  });

  factory CurriculumSubject.fromJson(Map<String, Object?> json) => CurriculumSubject(
    id: json['id']! as String,
    curriculumId: json['curriculum_id']! as String,
    educationLevelId: json['education_level_id']! as String,
    slug: json['slug']! as String,
    familyKey: json['family_key']! as String,
    boardCode: json['board_code'] as String?,
    paperNumber: json['paper_number'] as int?,
    name: LocalizedText.fromJson(json['name']),
    isActive: json['is_active'] as bool? ?? true,
    groups: [
      for (final g in (json['groups'] as List? ?? const <Object?>[]))
        SubjectGroupLink(
          groupId: (g! as Map<String, Object?>)['group_id']! as String,
          offering: (g as Map<String, Object?>)['offering']! as String,
        ),
    ],
  );

  final String id;
  final String curriculumId;
  final String educationLevelId;
  final String slug;
  final String familyKey;
  final String? boardCode;
  final int? paperNumber;
  final LocalizedText name;
  final bool isActive;
  final List<SubjectGroupLink> groups;
}

/// The editable part of a subject. A null board code or paper number clears it on the server.
@immutable
class SubjectFields {
  const SubjectFields({
    required this.familyKey,
    required this.name,
    required this.groups,
    this.boardCode,
    this.paperNumber,
  });

  final String familyKey;
  final LocalizedText name;
  final String? boardCode;
  final int? paperNumber;
  final List<SubjectGroupLink> groups;

  Map<String, Object?> toJson() => {
    'family_key': familyKey,
    'name': name.values,
    'board_code': boardCode,
    'paper_number': paperNumber,
    'groups': [for (final g in groups) g.toJson()],
  };
}

/// Admin reads and writes for subjects, chapters and topics (`/admin/academics`). The server enforces `academics.manage`.
abstract interface class AdminCurriculumRepository {
  Future<List<CurriculumSubject>> subjects();
  Future<List<CurriculumOption>> levels();
  Future<List<CurriculumOption>> curricula();
  Future<List<CurriculumOption>> groups(String levelId);
  Future<void> createSubject({
    required String curriculumId,
    required String levelId,
    required String slug,
    required SubjectFields fields,
  });
  Future<void> updateSubject(String id, {SubjectFields? fields, bool? isActive});
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

  List<CurriculumOption> _options(Object? json) => [
    for (final o in json! as List) CurriculumOption.fromJson(o as Map<String, Object?>),
  ];

  @override
  Future<List<CurriculumSubject>> subjects() async => (await api.get(
    '/admin/academics/subjects',
    decode: (j) => [for (final s in j! as List) CurriculumSubject.fromJson(s as Map<String, Object?>)],
  )).data;

  @override
  Future<List<CurriculumOption>> levels() async => (await api.get('/admin/academics/levels', decode: _options)).data;

  @override
  Future<List<CurriculumOption>> curricula() async =>
      (await api.get('/admin/academics/curricula', decode: _options)).data;

  @override
  Future<List<CurriculumOption>> groups(String levelId) async => (await api.get(
    '/admin/academics/groups',
    query: {'education_level_id': levelId},
    decode: _options,
  )).data;

  @override
  Future<void> createSubject({
    required String curriculumId,
    required String levelId,
    required String slug,
    required SubjectFields fields,
  }) async {
    await api.post(
      '/admin/academics/subjects',
      body: {'curriculum_id': curriculumId, 'education_level_id': levelId, 'slug': slug, ...fields.toJson()},
      decode: _ignore,
    );
  }

  @override
  Future<void> updateSubject(String id, {SubjectFields? fields, bool? isActive}) async {
    await api.patch(
      '/admin/academics/subjects/$id',
      body: {...?fields?.toJson(), 'is_active': ?isActive},
      decode: _ignore,
    );
  }

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
