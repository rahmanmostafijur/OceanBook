import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../academics/admin_curriculum_api.dart';
import 'admin_question_api.dart';
import 'answer_drafts.dart';
import 'content_text.dart';
import 'creative_parts.dart';
import 'option_fields.dart';
import 'question_classification.dart';
import 'question_detail_page.dart' show adminQuestionProvider;
import 'question_labels.dart';
import 'questions_page.dart' show adminQuestionsProvider;

const editableTypes = [
  QuestionType.mcqSingle,
  QuestionType.mcqMulti,
  QuestionType.trueFalse,
  QuestionType.creative,
  QuestionType.shortAnswer,
  QuestionType.fillBlank,
  QuestionType.matching,
];
const _optionTypes = [QuestionType.mcqSingle, QuestionType.mcqMulti, QuestionType.trueFalse];
const _fieldWidth = 220.0;

/// Creates a question, or edits one when [questionId] is given. Covers the option-based types (single
/// and multiple choice, true/false), creative (stimulus plus parts), short answer, fill in the blank and
/// matching questions in one source language, with plain text and `$maths$`. Anything else (other types, images, formatting) is shown as not
/// editable here rather than risk losing content.
class QuestionEditorPage extends ConsumerWidget {
  const QuestionEditorPage({this.questionId, super.key});

  final String? questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final id = questionId;
    if (id == null) return const _EditorForm();
    return switch (ref.watch(adminQuestionProvider(id))) {
      AsyncValue(:final value?) => _EditorForm(question: value),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminQuestionProvider(id)),
      ),
      _ => PageLoading(semanticLabel: l10n.commonLoading),
    };
  }
}

class _EditorForm extends ConsumerStatefulWidget {
  const _EditorForm({this.question});

  final AdminQuestion? question;

  @override
  ConsumerState<_EditorForm> createState() => _EditorFormState();
}

class _EditorFormState extends ConsumerState<_EditorForm> {
  final _form = GlobalKey<FormState>();
  final _stem = TextEditingController();
  final _stimulus = TextEditingController();
  final _modelAnswer = TextEditingController();
  final _guidance = TextEditingController();
  BlankAnswers _blanks = BlankAnswers.empty();
  MatchingDraft? _matching;
  final _explanation = TextEditingController();
  final _marks = TextEditingController(text: '1');
  final _entitlement = TextEditingController();
  final _note = TextEditingController();
  final List<OptionDraft> _options = [];
  final List<PartDraft> _parts = [];
  Map<String, Object?> _stimulusDocs = const {};
  String? _stimulusText;
  QuestionType _type = QuestionType.mcqSingle;
  String _locale = 'bn';
  int? _difficulty;
  String _access = 'free';
  String? _levelId;
  String? _subjectId;
  String? _chapterId;
  String? _topicId;
  List<CurriculumOption> _levels = const [];
  List<CurriculumSubject> _subjects = const [];
  List<CurriculumChapter> _chapters = const [];
  bool _loading = true;
  bool _supported = true;
  bool _busy = false;
  bool _optionsInvalid = false;
  bool _blanksInvalid = false;
  String? _error;

  AdminQuestion? get _existing => widget.question;
  bool get _creating => _existing == null;
  bool get _isTrueFalse => _type == QuestionType.trueFalse;
  bool get _isCreative => _type == QuestionType.creative;
  bool get _isShortAnswer => _type == QuestionType.shortAnswer;
  bool get _isFillBlank => _type == QuestionType.fillBlank;
  bool get _isMatching => _type == QuestionType.matching;
  bool get _hasOptions => _optionTypes.contains(_type);

  @override
  void initState() {
    super.initState();
    _seedFromQuestion();
    if (_supported) {
      if (_creating) _resetDrafts();
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    for (final c in [_stem, _stimulus, _modelAnswer, _guidance, _explanation, _marks, _entitlement, _note]) {
      c.dispose();
    }
    for (final o in _options) {
      o.dispose();
    }
    for (final p in _parts) {
      p.dispose();
    }
    _blanks.dispose();
    _matching?.dispose();
    super.dispose();
  }

  void _seedFromQuestion() {
    final q = _existing;
    if (q == null) return;
    final raw = q.rawContent;
    final locale = q.sourceLocale;
    final translation = ((raw['translations'] as Map?)?[locale] as Map?)?.cast<String, Object?>();
    final fill = q.type == QuestionType.fillBlank;
    final stem = textFromDoc(translation?['stem'] as Map<String, Object?>?, allowBlanks: fill);
    final explanation = textFromDoc(translation?['explanation'] as Map<String, Object?>?);
    final options = <OptionDraft>[];
    var optionsOk = true;
    for (final o in (raw['options'] as List? ?? const <Object?>[]).cast<Map<String, Object?>>()) {
      final text = textFromDoc(((o['content'] as Map?)?[locale]) as Map<String, Object?>?);
      if (text == null) optionsOk = false;
      options.add(
        OptionDraft(label: o['label']! as String, text: text ?? '', correct: (o['is_correct'] as bool?) ?? false),
      );
    }
    final parts = <PartDraft>[];
    var partsOk = true;
    for (final p in (raw['parts'] as List? ?? const <Object?>[]).cast<Map<String, Object?>>()) {
      final prompt = textFromDoc(((p['prompt'] as Map?)?[locale]) as Map<String, Object?>?);
      if (prompt == null || (p['cognitive_level'] as String?) == null) partsOk = false;
      parts.add(
        PartDraft(
          label: p['label']! as String,
          prompt: prompt ?? '',
          marks: formatMarks(double.parse('${p['marks']}')),
          level: (p['cognitive_level'] as String?) ?? cognitiveLevels.first,
        ),
      );
    }
    final creative = q.type == QuestionType.creative;
    final modelAnswer = textFromDoc(translation?['model_answer'] as Map<String, Object?>?);
    final guidance = textFromDoc(translation?['marking_guidance'] as Map<String, Object?>?);
    final spec = (raw['answer_spec'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final blanks = fill ? BlankAnswers.fromSpec(spec) : null;
    final matching = q.type == QuestionType.matching ? MatchingDraft.fromSpec(spec) : null;
    final specOk = switch (q.type) {
      QuestionType.fillBlank => blanks != null,
      QuestionType.matching => matching != null,
      _ => spec.isEmpty,
    };
    _supported =
        specOk &&
        modelAnswer != null &&
        guidance != null &&
        editableTypes.contains(q.type) &&
        stem != null &&
        explanation != null &&
        optionsOk &&
        partsOk &&
        creative == parts.isNotEmpty;
    _parts.addAll(parts);
    _modelAnswer.text = modelAnswer ?? '';
    _guidance.text = guidance ?? '';
    if (blanks != null) _blanks = blanks;
    _matching = matching;
    _type = q.type;
    _locale = locale;
    _stem.text = stem ?? '';
    _explanation.text = explanation ?? '';
    _options.addAll(options);
    _marks.text = _trimMarks(q.marks);
    _difficulty = q.difficulty;
    _access = (raw['access_level'] as String?) ?? 'free';
    _entitlement.text = (raw['required_entitlement_key'] as String?) ?? '';
    _levelId = raw['education_level_id'] as String?;
    _subjectId = raw['subject_id'] as String?;
    _chapterId = raw['chapter_id'] as String?;
    _topicId = raw['topic_id'] as String?;
  }

  String _trimMarks(double marks) => formatMarks(marks);

  Future<void> _load() async {
    final repo = ref.read(adminCurriculumRepositoryProvider);
    try {
      final results = await Future.wait([repo.levels(), repo.subjects()]);
      _levels = results[0] as List<CurriculumOption>;
      _subjects = results[1] as List<CurriculumSubject>;
      if (_subjectId != null) _chapters = await repo.chapters(_subjectId!);
      await _loadStimulus();
      if (mounted) setState(() => _loading = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = adminFailureMessage(ObLocalizations.of(context), error);
      });
    }
  }

  /// The passage of an existing creative question. One the plain-text format cannot reproduce keeps the
  /// whole question read-only, like any other content the editor would otherwise lose.
  Future<void> _loadStimulus() async {
    final id = _existing?.stimulusId;
    if (!_isCreative || id == null) return;
    final stimulus = await ref.read(adminQuestionRepositoryProvider).stimulus(id);
    final doc = stimulus.translations[_locale] as Map<String, Object?>?;
    final text = doc == null ? null : textFromDoc(doc);
    if (text == null) {
      _supported = false;
      return;
    }
    _stimulusDocs = stimulus.translations;
    _stimulusText = text;
    _stimulus.text = text;
  }

  void _resetDrafts() {
    _resetOptions();
    _resetParts();
    _blanks.dispose();
    _blanks = BlankAnswers.empty();
    _matching?.dispose();
    _matching = _isMatching ? MatchingDraft.empty() : null;
  }

  void _resetParts() {
    for (final p in _parts) {
      p.dispose();
    }
    _parts.clear();
    if (!_isCreative) return;
    for (var i = 0; i < defaultPartMarks.length; i++) {
      _parts.add(
        PartDraft(label: answerLabels[_locale]![i], prompt: '', marks: defaultPartMarks[i], level: cognitiveLevels[i]),
      );
    }
  }

  void _resetOptions() {
    for (final o in _options) {
      o.dispose();
    }
    _options.clear();
    if (!_hasOptions) return;
    final count = _isTrueFalse ? 2 : 4;
    for (var i = 0; i < count; i++) {
      _options.add(
        OptionDraft(label: answerLabels[_locale]![i], text: _isTrueFalse ? trueFalseText[_locale]![i] : ''),
      );
    }
  }

  Future<void> _pickSubject(String? id) async {
    setState(() {
      _subjectId = id;
      _chapterId = null;
      _topicId = null;
      _chapters = const [];
    });
    if (id == null) return;
    try {
      final chapters = await ref.read(adminCurriculumRepositoryProvider).chapters(id);
      if (mounted && _subjectId == id) setState(() => _chapters = chapters);
    } on Object catch (error) {
      if (mounted) setState(() => _error = adminFailureMessage(ObLocalizations.of(context), error));
    }
  }

  void _setCorrect(int index, bool value) => setState(() {
    if (_type != QuestionType.mcqMulti) {
      for (final o in _options) {
        o.correct = false;
      }
    }
    _options[index].correct = value;
    _optionsInvalid = false;
  });

  bool _correctCountValid() {
    final correct = _options.where((o) => o.correct).length;
    return _type == QuestionType.mcqMulti ? correct >= 1 : correct == 1;
  }

  Map<String, Object?> _buildContent() {
    final raw = _existing?.rawContent ?? const <String, Object?>{};
    final translations = {...?(raw['translations'] as Map?)?.cast<String, Object?>()};
    final current = {...?(translations[_locale] as Map?)?.cast<String, Object?>()};
    current['stem'] = docFromText(_stem.text, allowBlanks: _isFillBlank);
    if (_isShortAnswer) current['model_answer'] = docFromText(_modelAnswer.text);
    if (_isShortAnswer) {
      if (_guidance.text.trim().isEmpty) {
        current.remove('marking_guidance');
      } else {
        current['marking_guidance'] = docFromText(_guidance.text);
      }
    }
    if (_explanation.text.trim().isEmpty) {
      current.remove('explanation');
    } else {
      current['explanation'] = docFromText(_explanation.text);
    }
    translations[_locale] = current;

    final rawOptions = (raw['options'] as List? ?? const <Object?>[]).cast<Map<String, Object?>>();
    Map<String, Object?>? rawFor(int i, String label) =>
        rawOptions.where((r) => r['label'] == label).firstOrNull ?? (i < rawOptions.length ? rawOptions[i] : null);
    final options = [
      for (final (i, o) in _options.indexed)
        {
          ...?rawFor(i, o.label.text.trim()),
          'label': o.label.text.trim(),
          'is_correct': o.correct,
          'content': {
            ...?(rawFor(i, o.label.text.trim())?['content'] as Map?)?.cast<String, Object?>(),
            _locale: docFromText(o.text.text),
          },
        },
    ];
    final entitled = _access == 'entitled';
    final rawParts = (raw['parts'] as List? ?? const <Object?>[]).cast<Map<String, Object?>>();
    Map<String, Object?>? rawPartFor(int i, String label) =>
        rawParts.where((r) => r['label'] == label).firstOrNull ?? (i < rawParts.length ? rawParts[i] : null);
    final parts = [
      for (final (i, p) in _parts.indexed)
        {
          ...?rawPartFor(i, p.label.text.trim()),
          'label': p.label.text.trim(),
          'cognitive_level': p.level,
          'marks': p.marks.text.trim(),
          'prompt': {
            ...?(rawPartFor(i, p.label.text.trim())?['prompt'] as Map?)?.cast<String, Object?>(),
            _locale: docFromText(p.prompt.text),
          },
        },
    ];
    return {
      ...raw,
      'type': _type.wire,
      'source_locale': _locale,
      'education_level_id': _levelId,
      'subject_id': _subjectId,
      'chapter_id': _chapterId,
      'topic_id': _chapterId == null ? null : _topicId,
      'difficulty': _difficulty,
      'marks': _isCreative ? totalPartMarks(_parts).toStringAsFixed(2) : _marks.text.trim(),
      'access_level': _access,
      'required_entitlement_key': entitled ? _entitlement.text.trim() : null,
      'translations': translations,
      'options': options,
      'parts': parts,
      if (_isFillBlank)
        'answer_spec': _blanks.toSpec((raw['answer_spec'] as Map?)?.cast<String, Object?>() ?? const {}),
      if (_isMatching) 'answer_spec': _matching!.toSpec(),
    };
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    final optionsOk = !_hasOptions || _correctCountValid();
    final blanksOk = !_isFillBlank || BlankAnswers.markersValid(_stem.text);
    setState(() => _blanksInvalid = !blanksOk);
    setState(() => _optionsInvalid = !optionsOk);
    if (!valid || !optionsOk || !blanksOk) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = ObLocalizations.of(context);
    final repo = ref.read(adminQuestionRepositoryProvider);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    try {
      final stimulusId = await _saveStimulus(repo);
      final content = {..._buildContent(), if (_isCreative) 'stimulus_id': stimulusId};
      final saved = _creating
          ? await repo.createQuestion(content, changeNote: note)
          : await repo.updateQuestion(_existing!.id, content, changeNote: note);
      ref
        ..invalidate(adminQuestionsProvider)
        ..invalidate(adminQuestionProvider(saved.id));
      if (mounted) context.go('/questions/${saved.id}');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminFailureMessage(l10n, error);
      });
    }
  }

  /// A stimulus used by live questions cannot be changed, so an edited passage becomes a new stimulus
  /// (keeping the other translations) and the question points to it. Unchanged text keeps the old one.
  Future<String?> _saveStimulus(AdminQuestionRepository repo) async {
    if (!_isCreative) return null;
    final existingId = _existing?.stimulusId;
    if (existingId != null && _stimulus.text == _stimulusText) return existingId;
    final saved = await repo.createStimulus(_locale, {..._stimulusDocs, _locale: docFromText(_stimulus.text)});
    return saved.id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    if (!_supported) {
      return EmptyState(
        icon: Icons.edit_off_outlined,
        title: l10n.adminEditQuestion,
        message: l10n.adminEditorUnsupported,
      );
    }
    if (_loading) return PageLoading(semanticLabel: l10n.commonLoading);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth + 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _creating ? l10n.adminNewQuestion : l10n.adminEditQuestion,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ..._basics(l10n),
                  ..._contentFields(l10n),
                  if (_isMatching)
                    MatchingEditor(draft: _matching!, onChanged: () => setState(() {}))
                  else if (_isCreative)
                    CreativePartsEditor(
                      parts: _parts,
                      onAdd: _addPart,
                      onRemove: _removePart,
                      onChanged: () => setState(() {}),
                    )
                  else if (_hasOptions)
                    OptionsEditor(
                      options: _options,
                      type: _type,
                      locale: _locale,
                      invalid: _optionsInvalid,
                      onCorrect: _setCorrect,
                      onRemove: (i) => setState(() {
                        _options.removeAt(i).dispose();
                        _optionsInvalid = false;
                      }),
                      onAdd: () => setState(
                        () => _options.add(OptionDraft(label: answerLabels[_locale]![_options.length], text: '')),
                      ),
                    ),
                  QuestionClassification(
                    levels: _levels,
                    subjects: _subjects,
                    chapters: _chapters,
                    levelId: _levelId,
                    subjectId: _subjectId,
                    chapterId: _chapterId,
                    topicId: _topicId,
                    onLevel: (v) => setState(() {
                      _levelId = v;
                      _pickSubject(null);
                    }),
                    onSubject: _pickSubject,
                    onChapter: (v) => setState(() {
                      _chapterId = v;
                      _topicId = null;
                    }),
                    onTopic: (v) => setState(() => _topicId = v),
                  ),
                  ..._footer(l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addPart() => setState(() {
    final labels = answerLabels[_locale]!;
    _parts.add(
      PartDraft(
        label: labels[_parts.length.clamp(0, labels.length - 1)],
        prompt: '',
        marks: '1',
        level: cognitiveLevels.first,
      ),
    );
  });

  void _removePart(int index) => setState(() => _parts.removeAt(index).dispose());

  String? _required(ObLocalizations l10n, String? v) => isValidContentText(v ?? '') ? null : l10n.errorValidation;

  List<Widget> _basics(ObLocalizations l10n) => [
    if (_creating) ...[
      DropdownButtonFormField<QuestionType>(
        key: const Key('question-type'),
        initialValue: _type,
        decoration: InputDecoration(labelText: l10n.adminFieldType),
        items: [
          for (final t in editableTypes) DropdownMenuItem(value: t, child: Text(adminQuestionTypeLabel(l10n, t))),
        ],
        onChanged: (t) => setState(() {
          _type = t!;
          _resetDrafts();
        }),
      ),
      const SizedBox(height: AppSpacing.sm),
      DropdownButtonFormField<String>(
        key: const Key('question-language'),
        initialValue: _locale,
        decoration: InputDecoration(labelText: l10n.adminFieldLanguage),
        items: [
          DropdownMenuItem(value: 'bn', child: Text(l10n.adminLanguageBangla)),
          DropdownMenuItem(value: 'en', child: Text(l10n.adminLanguageEnglish)),
        ],
        onChanged: (v) => setState(() {
          _locale = v!;
          _resetDrafts();
        }),
      ),
      const SizedBox(height: AppSpacing.sm),
    ],
  ];

  List<Widget> _contentFields(ObLocalizations l10n) => [
    TextFormField(
      key: const Key('question-stem'),
      controller: _stem,
      minLines: 3,
      maxLines: 8,
      decoration: InputDecoration(
        labelText: l10n.adminFieldStem,
        helperText: _isFillBlank ? '${l10n.adminMathHint} ${l10n.adminBlankHint}' : l10n.adminMathHint,
        helperMaxLines: 3,
      ),
      onChanged: _isFillBlank ? (v) => setState(() => _blanks.syncWith(v)) : null,
      validator: (v) => _required(l10n, v),
    ),
    if (_isFillBlank) ...[
      if (_blanksInvalid)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Semantics(
            liveRegion: true,
            child: Text(
              l10n.adminBlankMarkersInvalid,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      BlankAnswersEditor(blanks: _blanks),
    ],
    if (_isShortAnswer) ...[
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('question-model-answer'),
        controller: _modelAnswer,
        minLines: 2,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: l10n.adminModelAnswer,
          helperText: l10n.adminMathHint,
          helperMaxLines: 2,
        ),
        validator: (v) => _required(l10n, v),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('question-guidance'),
        controller: _guidance,
        minLines: 2,
        maxLines: 6,
        decoration: InputDecoration(labelText: l10n.adminMarkingGuidance),
        validator: (v) => (v?.trim().isEmpty ?? true) || isValidContentText(v!) ? null : l10n.errorValidation,
      ),
    ],
    if (_isCreative) ...[
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('question-stimulus'),
        controller: _stimulus,
        minLines: 3,
        maxLines: 10,
        decoration: InputDecoration(
          labelText: l10n.adminFieldStimulus,
          helperText: l10n.adminMathHint,
          helperMaxLines: 2,
        ),
        validator: (v) => _required(l10n, v),
      ),
    ],
    const SizedBox(height: AppSpacing.sm),
    TextFormField(
      key: const Key('question-explanation'),
      controller: _explanation,
      minLines: 2,
      maxLines: 6,
      decoration: InputDecoration(labelText: l10n.adminFieldExplanation),
      validator: (v) => (v?.trim().isEmpty ?? true) || isValidContentText(v!) ? null : l10n.errorValidation,
    ),
  ];

  List<Widget> _footer(ObLocalizations l10n) => [
    const SizedBox(height: AppSpacing.lg),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (!_isCreative)
          SizedBox(
            width: _fieldWidth,
            child: TextFormField(
              key: const Key('question-marks'),
              controller: _marks,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.adminFieldMarks),
              validator: (v) {
                final marks = double.tryParse(v?.trim() ?? '');
                return marks == null || marks <= 0 || marks > 999 ? l10n.errorValidation : null;
              },
            ),
          ),
        SizedBox(
          width: _fieldWidth,
          child: DropdownButtonFormField<int?>(
            key: const Key('question-difficulty'),
            isExpanded: true,
            initialValue: _difficulty,
            decoration: InputDecoration(labelText: l10n.adminFieldDifficulty),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.adminDifficultyNone)),
              for (var d = 1; d <= 5; d++) DropdownMenuItem(value: d, child: Text(l10n.questionDifficultyLevel(d))),
            ],
            onChanged: (v) => setState(() => _difficulty = v),
          ),
        ),
        SizedBox(
          width: _fieldWidth,
          child: DropdownButtonFormField<String>(
            key: const Key('question-access'),
            isExpanded: true,
            initialValue: _access,
            decoration: InputDecoration(labelText: l10n.adminFieldAccess),
            items: [
              DropdownMenuItem(value: 'free', child: Text(l10n.adminAccessFree)),
              DropdownMenuItem(value: 'registered', child: Text(l10n.adminAccessRegistered)),
              DropdownMenuItem(value: 'entitled', child: Text(l10n.adminAccessEntitled)),
            ],
            onChanged: (v) => setState(() => _access = v!),
          ),
        ),
      ],
    ),
    if (_access == 'entitled') ...[
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('question-entitlement'),
        controller: _entitlement,
        decoration: InputDecoration(labelText: l10n.adminEntitlementKey),
        validator: (v) => (v?.trim().isEmpty ?? true) ? l10n.errorValidation : null,
      ),
    ],
    if (!_creating) ...[
      const SizedBox(height: AppSpacing.sm),
      TextFormField(
        key: const Key('question-note'),
        controller: _note,
        decoration: InputDecoration(labelText: l10n.adminChangeNote),
      ),
    ],
    if (_error != null)
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Semantics(
          liveRegion: true,
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      ),
    const SizedBox(height: AppSpacing.lg),
    Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _busy ? null : () => context.go(_creating ? '/questions' : '/questions/${_existing!.id}'),
          child: Text(l10n.actionCancel),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(key: const Key('question-save'), onPressed: _busy ? null : _save, child: Text(l10n.actionSave)),
      ],
    ),
  ];
}
