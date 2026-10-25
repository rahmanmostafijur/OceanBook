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

/// A shared passage (উদ্দীপক) a creative question is built on.
@immutable
class AdminStimulus {
  const AdminStimulus({required this.id, required this.sourceLocale, required this.translations});

  factory AdminStimulus.fromJson(Map<String, Object?> json) => AdminStimulus(
    id: _req(json, 'id'),
    sourceLocale: _req(json, 'source_locale'),
    translations: (json['translations']! as Map).cast<String, Object?>(),
  );

  final String id;
  final String sourceLocale;

  /// ContentDoc JSON by locale.
  final Map<String, Object?> translations;
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
class AdminPaperItem {
  const AdminPaperItem({required this.questionId, required this.itemNumber, this.marks});

  factory AdminPaperItem.fromJson(Map<String, Object?> json) => AdminPaperItem(
    questionId: _req(json, 'question_id'),
    itemNumber: _req(json, 'item_number'),
    marks: json['marks'] == null ? null : double.parse('${json['marks']}'),
  );

  final String questionId;
  final String itemNumber;

  /// Marks for this question in this paper, when they differ from the question's own.
  final double? marks;

  Map<String, Object?> toJson() => {
    'question_id': questionId,
    'item_number': itemNumber,
    if (marks != null) 'marks': marks!.toStringAsFixed(2),
  };
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
    this.educationLevelId,
    this.subjectId,
    this.academicGroupId,
    this.instructionMediumId,
    this.totalMarks,
    this.durationMinutes,
    this.boardIds = const [],
    this.accessLevel = 'free',
    this.requiredEntitlementKey,
    this.items = const [],
  });

  factory AdminPaper.fromJson(Map<String, Object?> json) {
    final boardIds = [for (final b in (json['board_ids'] as List?) ?? const <Object?>[]) '$b'];
    final items = _list((json['items'] as List?) ?? const <Object?>[], AdminPaperItem.fromJson);
    return AdminPaper(
      id: _req(json, 'id'),
      examYear: _req(json, 'exam_year'),
      examKind: _req(json, 'exam_kind'),
      section: _req(json, 'section'),
      status: _req(json, 'status'),
      title: json['title'] as String?,
      boardCount: boardIds.length,
      itemCount: items.length,
      educationLevelId: json['education_level_id'] as String?,
      subjectId: json['subject_id'] as String?,
      academicGroupId: json['academic_group_id'] as String?,
      instructionMediumId: json['instruction_medium_id'] as String?,
      totalMarks: json['total_marks'] == null ? null : double.parse('${json['total_marks']}'),
      durationMinutes: json['duration_minutes'] as int?,
      boardIds: boardIds,
      accessLevel: (json['access_level'] as String?) ?? 'free',
      requiredEntitlementKey: json['required_entitlement_key'] as String?,
      items: items,
    );
  }

  final String id;
  final int examYear;
  final String examKind;
  final String section;
  final String status;
  final String? title;
  final int boardCount;
  final int itemCount;
  final String? educationLevelId;
  final String? subjectId;
  final String? academicGroupId;
  final String? instructionMediumId;
  final double? totalMarks;
  final int? durationMinutes;
  final List<String> boardIds;
  final String accessLevel;
  final String? requiredEntitlementKey;
  final List<AdminPaperItem> items;
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
    String? subjectId,
    int page = 1,
    int pageSize = 25,
  });
  Future<AdminQuestion> question(String id);
  Future<AdminQuestion> createQuestion(Map<String, Object?> content, {String? changeNote});
  Future<AdminQuestion> updateQuestion(String id, Map<String, Object?> content, {String? changeNote});
  Future<AdminQuestion> act(String id, QuestionAction action, {String? comment, bool acknowledgeDuplicates = false});
  Future<AdminStimulus> stimulus(String id);

  /// Stimuli of live questions cannot be edited, so a changed passage is always saved as a new one.
  Future<AdminStimulus> createStimulus(String sourceLocale, Map<String, Object?> translations);
  Future<Paged<AdminPaper>> papers({String? status, int page = 1, int pageSize = 25});
  Future<AdminPaper> paper(String id);
  Future<AdminPaper> createPaper(Map<String, Object?> body);

  /// Only the fields in [patch] change; the server accepts edits to drafts only.
  Future<AdminPaper> updatePaper(String id, Map<String, Object?> patch);

  /// Replaces the paper's whole list of questions.
  Future<List<AdminPaperItem>> setPaperItems(String id, List<AdminPaperItem> items);
  Future<AdminPaper> publishPaper(String id);
  Future<AdminPaper> archivePaper(String id, String reason);
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
    String? subjectId,
    int page = 1,
    int pageSize = 25,
  }) async {
    final response = await api.get(
      '/admin/questions',
      query: {
        'status': status,
        'type': type?.wire,
        'subject_id': subjectId,
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

  AdminStimulus _stimulus(Object? json) => AdminStimulus.fromJson(json! as Map<String, Object?>);

  @override
  Future<AdminStimulus> stimulus(String id) async => (await api.get('/admin/stimuli/$id', decode: _stimulus)).data;

  @override
  Future<AdminStimulus> createStimulus(String sourceLocale, Map<String, Object?> translations) async => (await api.post(
    '/admin/stimuli',
    body: {'source_locale': sourceLocale, 'translations': translations},
    decode: _stimulus,
  )).data;

  @override
  Future<Paged<AdminPaper>> papers({String? status, int page = 1, int pageSize = 25}) async {
    final response = await api.get(
      '/admin/question-papers',
      query: {'status': status, 'page': page, 'page_size': pageSize},
      decode: (j) => _list(j, AdminPaper.fromJson),
    );
    return Paged(rows: response.data, total: _total(response, response.data.length));
  }

  AdminPaper _paper(Object? json) => AdminPaper.fromJson(json! as Map<String, Object?>);

  @override
  Future<AdminPaper> paper(String id) async => (await api.get('/admin/question-papers/$id', decode: _paper)).data;

  @override
  Future<AdminPaper> createPaper(Map<String, Object?> body) async =>
      (await api.post('/admin/question-papers', body: body, decode: _paper)).data;

  @override
  Future<AdminPaper> updatePaper(String id, Map<String, Object?> patch) async =>
      (await api.patch('/admin/question-papers/$id', body: patch, decode: _paper)).data;

  @override
  Future<List<AdminPaperItem>> setPaperItems(String id, List<AdminPaperItem> items) async => (await api.put(
    '/admin/question-papers/$id/items',
    body: {
      'items': [for (final i in items) i.toJson()],
    },
    decode: (j) => _list(j, AdminPaperItem.fromJson),
  )).data;

  @override
  Future<AdminPaper> publishPaper(String id) async =>
      (await api.post('/admin/question-papers/$id/publish', decode: _paper)).data;

  @override
  Future<AdminPaper> archivePaper(String id, String reason) async =>
      (await api.post('/admin/question-papers/$id/archive', body: {'reason': reason}, decode: _paper)).data;
}

final adminQuestionRepositoryProvider = Provider<AdminQuestionRepository>(
  (ref) => AdminQuestionApi(ref.watch(adminApiProvider), locale: ref.watch(adminLocaleProvider).languageCode),
);
