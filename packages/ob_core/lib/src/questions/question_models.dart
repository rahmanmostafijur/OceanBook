import 'package:meta/meta.dart';

import '../catalog/catalog_models.dart' show AccessLevel;

/// Question-bank value types mirroring the public `/questions`, `/question-papers` and `/academics`
/// contract (backend `app/questionbank/schemas.py`, `app/academics/schemas.py`). Text is resolved for the
/// request locale; documents arrive as ContentDoc JSON for the renderer.

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) decode) => [
  for (final item in (raw as List?) ?? const <Object?>[]) decode(item! as Map<String, Object?>),
];

double _num(Object? raw) => raw is num ? raw.toDouble() : double.parse(raw! as String);

/// Names arrive as `{bn, en}` objects; pick the requested locale, then Bangla, then English.
String _label(Object? raw, String locale) {
  final names = (raw as Map?)?.cast<String, String>() ?? const {};
  return names[locale] ?? names['bn'] ?? names['en'] ?? (names.isEmpty ? '' : names.values.first);
}

enum QuestionType {
  mcqSingle('mcq_single'),
  mcqMulti('mcq_multi'),
  trueFalse('true_false'),
  shortAnswer('short_answer'),
  creative('creative'),
  fillBlank('fill_blank'),
  matching('matching'),
  unknown('unknown');

  const QuestionType(this.wire);
  final String wire;

  static QuestionType fromWire(String? value) =>
      QuestionType.values.firstWhere((t) => t.wire == value, orElse: () => QuestionType.unknown);
}

@immutable
class EducationLevelRef {
  const EducationLevelRef({required this.id, required this.key, required this.name});

  factory EducationLevelRef.fromJson(Map<String, Object?> json, String locale) =>
      EducationLevelRef(id: json['id']! as String, key: json['key']! as String, name: _label(json['name'], locale));

  final String id;
  final String key;
  final String name;
}

@immutable
class BoardRef {
  const BoardRef({required this.id, required this.key, required this.name});

  factory BoardRef.fromJson(Map<String, Object?> json, String locale) =>
      BoardRef(id: json['id']! as String, key: json['key']! as String, name: _label(json['name'], locale));

  final String id;
  final String key;
  final String name;
}

/// A board paper is its own subject row; `familyKey` groups the papers of one subject (Physics 1st/2nd).
@immutable
class SubjectRef {
  const SubjectRef({required this.id, required this.familyKey, required this.name, this.paperNumber, this.boardCode});

  factory SubjectRef.fromJson(Map<String, Object?> json, String locale) => SubjectRef(
    id: json['id']! as String,
    familyKey: json['family_key']! as String,
    name: _label(json['name'], locale),
    paperNumber: (json['paper_number'] as num?)?.toInt(),
    boardCode: json['board_code'] as String?,
  );

  final String id;
  final String familyKey;
  final String name;
  final int? paperNumber;
  final String? boardCode;
}

@immutable
class TopicRef {
  const TopicRef({required this.id, required this.name});

  final String id;
  final String name;
}

@immutable
class ChapterRef {
  const ChapterRef({required this.id, required this.number, required this.name, this.topics = const []});

  factory ChapterRef.fromJson(Map<String, Object?> json, String locale) => ChapterRef(
    id: json['id']! as String,
    number: (json['number']! as num).toInt(),
    name: _label(json['name'], locale),
    topics: _list(json['topics'], (t) => TopicRef(id: t['id']! as String, name: _label(t['name'], locale))),
  );

  final String id;
  final int number;
  final String name;
  final List<TopicRef> topics;
}

/// Filters of the public question list. Filtering happens on the server.
@immutable
class QuestionQuery {
  const QuestionQuery({
    this.levelId,
    this.subjectId,
    this.chapterId,
    this.topicId,
    this.type,
    this.difficulty,
    this.boardId,
    this.year,
    this.search,
  });

  final String? levelId;
  final String? subjectId;
  final String? chapterId;
  final String? topicId;
  final QuestionType? type;
  final int? difficulty;
  final String? boardId;
  final int? year;
  final String? search;

  QuestionQuery copyWith({
    String? levelId,
    String? subjectId,
    String? chapterId,
    String? topicId,
    QuestionType? type,
    int? difficulty,
    String? boardId,
    int? year,
    String? search,
    bool clearSubject = false,
    bool clearChapter = false,
    bool clearType = false,
    bool clearDifficulty = false,
    bool clearBoard = false,
    bool clearYear = false,
  }) => QuestionQuery(
    levelId: levelId ?? this.levelId,
    // Changing the subject drops the chapter and topic, which belong to it.
    subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
    chapterId: (clearSubject || clearChapter) ? null : (chapterId ?? this.chapterId),
    topicId: (clearSubject || clearChapter) ? null : (topicId ?? this.topicId),
    type: clearType ? null : (type ?? this.type),
    difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
    boardId: clearBoard ? null : (boardId ?? this.boardId),
    year: clearYear ? null : (year ?? this.year),
    search: search ?? this.search,
  );

  bool get hasNarrowingFilters =>
      subjectId != null ||
      chapterId != null ||
      type != null ||
      difficulty != null ||
      boardId != null ||
      year != null ||
      (search?.isNotEmpty ?? false);

  Map<String, Object?> toQuery() => {
    'level': levelId,
    'subject': subjectId,
    'chapter': chapterId,
    'topic': topicId,
    'type': type?.wire,
    'difficulty': difficulty,
    'board': boardId,
    'year': year,
    'q': (search?.length ?? 0) >= 2 ? search : null,
  };

  @override
  bool operator ==(Object other) =>
      other is QuestionQuery &&
      other.levelId == levelId &&
      other.subjectId == subjectId &&
      other.chapterId == chapterId &&
      other.topicId == topicId &&
      other.type == type &&
      other.difficulty == difficulty &&
      other.boardId == boardId &&
      other.year == year &&
      other.search == search;

  @override
  int get hashCode => Object.hash(levelId, subjectId, chapterId, topicId, type, difficulty, boardId, year, search);
}

@immutable
class QuestionCard {
  const QuestionCard({
    required this.id,
    required this.type,
    required this.locale,
    required this.stemText,
    required this.marks,
    required this.accessLevel,
    this.difficulty,
    this.availableLocales = const [],
  });

  factory QuestionCard.fromJson(Map<String, Object?> json) => QuestionCard(
    id: json['id']! as String,
    type: QuestionType.fromWire(json['type'] as String?),
    locale: json['locale']! as String,
    stemText: json['stem_text']! as String,
    marks: _num(json['marks']),
    difficulty: (json['difficulty'] as num?)?.toInt(),
    accessLevel: AccessLevel.fromWire(json['access_level'] as String?),
    availableLocales: [for (final l in (json['available_locales'] as List?) ?? const []) l as String],
  );

  final String id;
  final QuestionType type;
  final String locale;
  final String stemText;
  final double marks;
  final int? difficulty;
  final AccessLevel accessLevel;
  final List<String> availableLocales;
}

@immutable
class QuestionOption {
  const QuestionOption({required this.id, required this.label, required this.content, this.isCorrect});

  factory QuestionOption.fromJson(Map<String, Object?> json) => QuestionOption(
    id: json['id']! as String,
    label: json['label']! as String,
    content: json['content']! as Map<String, Object?>,
    isCorrect: json['is_correct'] as bool?,
  );

  final String id;
  final String label;

  /// ContentDoc JSON.
  final Map<String, Object?> content;

  /// Null unless the server allows this caller to see answers.
  final bool? isCorrect;
}

@immutable
class QuestionPart {
  const QuestionPart({
    required this.label,
    required this.cognitiveLevel,
    required this.marks,
    required this.prompt,
    this.modelAnswer,
  });

  factory QuestionPart.fromJson(Map<String, Object?> json) => QuestionPart(
    label: json['label']! as String,
    cognitiveLevel: json['cognitive_level']! as String,
    marks: _num(json['marks']),
    prompt: json['prompt']! as Map<String, Object?>,
    modelAnswer: json['model_answer'] as Map<String, Object?>?,
  );

  final String label;
  final String cognitiveLevel;
  final double marks;
  final Map<String, Object?> prompt;
  final Map<String, Object?>? modelAnswer;
}

@immutable
class QuestionAccess {
  const QuestionAccess({required this.level, required this.canViewAnswers, required this.reasons});

  factory QuestionAccess.fromJson(Map<String, Object?> json) => QuestionAccess(
    level: AccessLevel.fromWire(json['level'] as String?),
    canViewAnswers: json['can_view_answers']! as bool,
    reasons: [for (final r in (json['reasons'] as List?) ?? const []) r as String],
  );

  final AccessLevel level;

  /// The server's decision: when false the response carries no answers at all.
  final bool canViewAnswers;
  final List<String> reasons;
}

@immutable
class QuestionAppearance {
  const QuestionAppearance({required this.examYear, required this.examKind, required this.itemNumber});

  factory QuestionAppearance.fromJson(Map<String, Object?> json) => QuestionAppearance(
    examYear: (json['exam_year']! as num).toInt(),
    examKind: json['exam_kind']! as String,
    itemNumber: json['item_number']! as String,
  );

  final int examYear;
  final String examKind;
  final String itemNumber;
}

@immutable
class QuestionDetail {
  const QuestionDetail({
    required this.card,
    required this.stem,
    required this.options,
    required this.parts,
    required this.appearances,
    required this.access,
    this.stimulus,
    this.explanation,
    this.modelAnswer,
  });

  factory QuestionDetail.fromJson(Map<String, Object?> json) => QuestionDetail(
    card: QuestionCard.fromJson(json),
    stem: json['stem']! as Map<String, Object?>,
    stimulus: json['stimulus'] as Map<String, Object?>?,
    options: _list(json['options'], QuestionOption.fromJson),
    parts: _list(json['parts'], QuestionPart.fromJson),
    appearances: _list(json['appearances'], QuestionAppearance.fromJson),
    access: QuestionAccess.fromJson(json['access']! as Map<String, Object?>),
    explanation: json['explanation'] as Map<String, Object?>?,
    modelAnswer: json['model_answer'] as Map<String, Object?>?,
  );

  final QuestionCard card;
  final Map<String, Object?> stem;
  final Map<String, Object?>? stimulus;
  final List<QuestionOption> options;
  final List<QuestionPart> parts;
  final List<QuestionAppearance> appearances;
  final QuestionAccess access;
  final Map<String, Object?>? explanation;
  final Map<String, Object?>? modelAnswer;
}
