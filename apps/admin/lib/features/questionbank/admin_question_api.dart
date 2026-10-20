import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';

import '../../core/providers.dart';
import '../catalog/admin_catalog_api.dart' show Paged;

/// Admin question-bank contract (`/admin/questions`, `/admin/question-papers`, `/admin/academics`). The
/// server enforces permissions, the review workflow, separation of duties and the provenance publish
/// gate; this layer only carries requests and results.

T _req<T>(Map<String, Object?> json, String key) => json[key] as T;

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) decode) => [
  for (final item in (raw as List?) ?? const <Object?>[]) decode(item! as Map<String, Object?>),
];

@immutable
class AdminQuestionRow {
  const AdminQuestionRow({
    required this.id,
    required this.type,
    required this.status,
    required this.version,
    required this.marks,
    required this.accessLevel,
    required this.stem,
    required this.updatedAt,
    this.pendingStatus,
    this.difficulty,
  });

  factory AdminQuestionRow.fromJson(Map<String, Object?> json) => AdminQuestionRow(
    id: _req(json, 'id'),
    type: QuestionType.fromWire(json['type'] as String?),
    status: _req(json, 'status'),
    pendingStatus: json['pending_status'] as String?,
    version: _req(json, 'version'),
    marks: double.parse('${json['marks']}'),
    difficulty: json['difficulty'] as int?,
    accessLevel: _req(json, 'access_level'),
    stem: _req(json, 'stem'),
    updatedAt: DateTime.parse(_req(json, 'updated_at')),
  );

  final String id;
  final QuestionType type;
  final String status;
  final String? pendingStatus;
  final int version;
  final double marks;
  final int? difficulty;
  final String accessLevel;
  final String stem;
  final DateTime updatedAt;
}

@immutable
class AdminOption {
  const AdminOption({required this.label, required this.isCorrect, required this.content});

  final String label;
  final bool isCorrect;

  /// ContentDoc JSON in the question's source locale (falls back to any locale).
  final Map<String, Object?> content;
}

@immutable
class AdminPart {
  const AdminPart({required this.label, required this.marks, required this.prompt});

  final String label;
  final double marks;
  final Map<String, Object?> prompt;
}

@immutable
class AdminQuestion {
  const AdminQuestion({
    required this.id,
    required this.type,
    required this.status,
    required this.revisionStatus,
    required this.version,
    required this.latestRevision,
    required this.marks,
    required this.sourceLocale,
    required this.stem,
    required this.options,
    required this.parts,
    required this.issues,
    this.rawContent = const {},
    this.pendingStatus,
    this.difficulty,
    this.stimulusId,
    this.explanation,
  });

  factory AdminQuestion.fromJson(Map<String, Object?> json) {
    final content = json['content']! as Map<String, Object?>;
    final locale = content['source_locale']! as String;
    final translations = content['translations']! as Map<String, Object?>;
    final source = (translations[locale] ?? translations.values.first)! as Map<String, Object?>;
    Map<String, Object?> pick(Object? docs) {
      final byLocale = (docs! as Map).cast<String, Object?>();
      return (byLocale[locale] ?? byLocale.values.first)! as Map<String, Object?>;
    }

    return AdminQuestion(
      id: _req(json, 'id'),
      type: QuestionType.fromWire(content['type'] as String?),
      status: _req(json, 'status'),
      pendingStatus: json['pending_status'] as String?,
      revisionStatus: _req(json, 'revision_status'),
      version: _req(json, 'version'),
      latestRevision: _req(json, 'latest_revision'),
      marks: double.parse('${content['marks']}'),
      difficulty: content['difficulty'] as int?,
      sourceLocale: locale,
      stimulusId: content['stimulus_id'] as String?,
      stem: source['stem']! as Map<String, Object?>,
      explanation: source['explanation'] as Map<String, Object?>?,
      options: _list(
        content['options'],
        (o) => AdminOption(
          label: _req(o, 'label'),
          isCorrect: (o['is_correct'] as bool?) ?? false,
          content: pick(o['content']),
        ),
      ),
      parts: _list(
        content['parts'],
        (p) => AdminPart(label: _req(p, 'label'), marks: double.parse('${p['marks']}'), prompt: pick(p['prompt'])),
      ),
      issues: [for (final i in (json['issues'] as List?) ?? const <Object?>[]) '$i'],
      rawContent: content,
    );
  }

  final String id;
  final QuestionType type;
  final String status;
  final String? pendingStatus;
  final String revisionStatus;
  final int version;
  final int latestRevision;
  final double marks;
  final int? difficulty;
  final String sourceLocale;
  final String? stimulusId;
  final Map<String, Object?> stem;
  final Map<String, Object?>? explanation;
  final List<AdminOption> options;
  final List<AdminPart> parts;

  /// Machine-readable completeness issues the server found in the latest revision.
  final List<String> issues;

  /// The full editable snapshot as the server returned it, so an edit can change some fields and
  /// send everything else back untouched (other translations, parts, answer spec).
  final Map<String, Object?> rawContent;

  /// The workflow state of the revision being worked on (the pending edit, or the question itself).
  String get workflowStatus => pendingStatus ?? status;
}

@immutable
class AdminPaper {
  const AdminPaper({
    required this.id,
    required this.examYear,
    required this.examKind,
    required this.section,
    required this.status,
    required this.boardCount,
    required this.itemCount,
    this.title,
  });

  factory AdminPaper.fromJson(Map<String, Object?> json) => AdminPaper(
    id: _req(json, 'id'),
    examYear: _req(json, 'exam_year'),
    examKind: _req(json, 'exam_kind'),
    section: _req(json, 'section'),
    status: _req(json, 'status'),
    title: json['title'] as String?,
    boardCount: ((json['board_ids'] as List?) ?? const []).length,
    itemCount: ((json['items'] as List?) ?? const []).length,
  );

  final String id;
  final int examYear;
  final String examKind;
  final String section;
  final String status;
  final String? title;
  final int boardCount;
  final int itemCount;
}

/// The reviewer's decision, or another workflow step. Reason/comment-bearing ones are audited server-side.
enum QuestionAction {
  submit('submit'),
  approve('review'),
  requestChanges('review'),
  reject('review'),
  publish('publish'),
  archive('archive'),
  restore('restore');

  const QuestionAction(this.path);

  final String path;

  bool get needsComment => this == requestChanges || this == reject || this == archive;
}

/// Actions the question's current workflow state allows. The server re-checks every transition,
/// permission and separation-of-duties rule.
List<QuestionAction> questionActionsFor(AdminQuestion question) {
  final workflow = question.workflowStatus;
  final pendingOnLive = question.pendingStatus != null;
  return switch (workflow) {
    'draft' || 'changes_requested' => [QuestionAction.submit, if (!pendingOnLive) QuestionAction.archive],
    'in_review' => [QuestionAction.approve, QuestionAction.requestChanges, QuestionAction.reject],
    'approved' => [QuestionAction.publish, QuestionAction.requestChanges],
    'published' => [QuestionAction.archive],
    'archived' => [QuestionAction.restore],
    _ => const [],
  };
}

abstract interface class AdminQuestionRepository {
  Future<Paged<AdminQuestionRow>> questions({
    String? status,
    QuestionType? type,
    bool needsReview = false,
    int page = 1,
    int pageSize = 25,
  });
  Future<AdminQuestion> question(String id);
  Future<AdminQuestion> createQuestion(Map<String, Object?> content, {String? changeNote});
  Future<AdminQuestion> updateQuestion(String id, Map<String, Object?> content, {String? changeNote});
  Future<AdminQuestion> act(String id, QuestionAction action, {String? comment, bool acknowledgeDuplicates = false});
  Future<Paged<AdminPaper>> papers({String? status, int page = 1, int pageSize = 25});
}

class AdminQuestionApi implements AdminQuestionRepository {
  AdminQuestionApi(this.api, {this.locale = 'en'});

  final ApiClient api;
  final String locale;

  int _total(ApiResponse<Object?> response, int fallback) {
    final page = response.page;
    return page is OffsetPageMeta ? page.total : fallback;
  }

  AdminQuestion _question(Object? json) => AdminQuestion.fromJson(json! as Map<String, Object?>);

  @override
  Future<Paged<AdminQuestionRow>> questions({
    String? status,
    QuestionType? type,
    bool needsReview = false,
    int page = 1,
    int pageSize = 25,
  }) async {
    final response = await api.get(
      '/admin/questions',
      query: {
        'status': status,
        'type': type?.wire,
        'needs_review': needsReview ? true : null,
        'page': page,
        'page_size': pageSize,
      },
      decode: (j) => _list(j, AdminQuestionRow.fromJson),
    );
    return Paged(rows: response.data, total: _total(response, response.data.length));
  }

  @override
  Future<AdminQuestion> question(String id) async => (await api.get('/admin/questions/$id', decode: _question)).data;

  @override
  Future<AdminQuestion> createQuestion(Map<String, Object?> content, {String? changeNote}) async => (await api.post(
    '/admin/questions',
    body: {'content': content, 'change_note': ?changeNote},
    decode: _question,
  )).data;

  @override
  Future<AdminQuestion> updateQuestion(String id, Map<String, Object?> content, {String? changeNote}) async =>
      (await api.put(
        '/admin/questions/$id',
        body: {'content': content, 'change_note': ?changeNote},
        decode: _question,
      )).data;

  @override
  Future<AdminQuestion> act(
    String id,
    QuestionAction action, {
    String? comment,
    bool acknowledgeDuplicates = false,
  }) async {
    final Object? body = switch (action) {
      QuestionAction.approve => {'decision': 'approve', 'comment': comment},
      QuestionAction.requestChanges => {'decision': 'request_changes', 'comment': comment},
      QuestionAction.reject => {'decision': 'reject', 'comment': comment},
      QuestionAction.publish => {'acknowledge_duplicates': acknowledgeDuplicates},
      QuestionAction.archive => {'reason': comment},
      _ => null,
    };
    return (await api.post('/admin/questions/$id/${action.path}', body: body, decode: _question)).data;
  }

  @override
  Future<Paged<AdminPaper>> papers({String? status, int page = 1, int pageSize = 25}) async {
    final response = await api.get(
      '/admin/question-papers',
      query: {'status': status, 'page': page, 'page_size': pageSize},
      decode: (j) => _list(j, AdminPaper.fromJson),
    );
    return Paged(rows: response.data, total: _total(response, response.data.length));
  }
}

final adminQuestionRepositoryProvider = Provider<AdminQuestionRepository>(
  (ref) => AdminQuestionApi(ref.watch(adminApiProvider), locale: ref.watch(adminLocaleProvider).languageCode),
);
