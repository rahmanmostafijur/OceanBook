import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../academics/admin_curriculum_api.dart';
import 'admin_question_api.dart';
import 'content_text.dart';
import 'question_detail_page.dart' show adminQuestionProvider;
import 'question_labels.dart';
import 'questions_page.dart' show adminQuestionsProvider;

const editableTypes = [QuestionType.mcqSingle, QuestionType.mcqMulti, QuestionType.trueFalse];
const _fieldWidth = 220.0;
const _minOptions = 2;
const _maxSingleOptions = 6;
const _maxMultiOptions = 8;
const _labels = {
  'bn': ['ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ', 'ছ', 'জ'],
  'en': ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'],
};
const _trueFalseText = {
  'bn': ['সত্য', 'মিথ্যা'],
  'en': ['True', 'False'],
};

/// Creates a question, or edits one when [questionId] is given. Covers the option-based types (single
/// and multiple choice, true/false) in one source language, with plain text and `$maths$`. Anything
/// else (other types, images, formatting) is shown as not editable here rather than risk losing content.
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

class _OptionDraft {
  _OptionDraft({required String label, required String text, this.correct = false})
    : label = TextEditingController(text: label),
      text = TextEditingController(text: text);

  final TextEditingController label;
  final TextEditingController text;
  bool correct;

  void dispose() {
    label.dispose();
    text.dispose();
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
  final _explanation = TextEditingController();
  final _marks = TextEditingController(text: '1');
  final _entitlement = TextEditingController();
  final _note = TextEditingController();
  final List<_OptionDraft> _options = [];
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
  String? _error;

  AdminQuestion? get _existing => widget.question;
  bool get _creating => _existing == null;
  bool get _isTrueFalse => _type == QuestionType.trueFalse;

  @override
  void initState() {
    super.initState();
    _seedFromQuestion();
    if (_supported) {
      if (_creating) _resetOptions();
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    for (final c in [_stem, _explanation, _marks, _entitlement, _note]) {
      c.dispose();
    }
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  void _seedFromQuestion() {
    final q = _existing;
    if (q == null) return;
    final raw = q.rawContent;
    final locale = q.sourceLocale;
    final translation = ((raw['translations'] as Map?)?[locale] as Map?)?.cast<String, Object?>();
    final stem = textFromDoc(translation?['stem'] as Map<String, Object?>?);
    final explanation = textFromDoc(translation?['explanation'] as Map<String, Object?>?);
    final options = <_OptionDraft>[];
    var optionsOk = true;
    for (final o in (raw['options'] as List? ?? const <Object?>[]).cast<Map<String, Object?>>()) {
      final text = textFromDoc(((o['content'] as Map?)?[locale]) as Map<String, Object?>?);
      if (text == null) optionsOk = false;
      options.add(
        _OptionDraft(label: o['label']! as String, text: text ?? '', correct: (o['is_correct'] as bool?) ?? false),
      );
    }
    _supported =
        editableTypes.contains(q.type) &&
        stem != null &&
        explanation != null &&
        optionsOk &&
        (raw['parts'] as List? ?? const []).isEmpty;
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

  String _trimMarks(double marks) => marks == marks.roundToDouble() ? '${marks.round()}' : '$marks';

  Future<void> _load() async {
    final repo = ref.read(adminCurriculumRepositoryProvider);
    try {
      final results = await Future.wait([repo.levels(), repo.subjects()]);
      _levels = results[0] as List<CurriculumOption>;
      _subjects = results[1] as List<CurriculumSubject>;
      if (_subjectId != null) _chapters = await repo.chapters(_subjectId!);
      if (mounted) setState(() => _loading = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = adminFailureMessage(ObLocalizations.of(context), error);
      });
    }
  }

  void _resetOptions() {
    for (final o in _options) {
      o.dispose();
    }
    _options.clear();
    final count = _isTrueFalse ? 2 : 4;
    for (var i = 0; i < count; i++) {
      _options.add(
        _OptionDraft(label: _labels[_locale]![i], text: _isTrueFalse ? _trueFalseText[_locale]![i] : ''),
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
    current['stem'] = docFromText(_stem.text);
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
    return {
      ...raw,
      'type': _type.wire,
      'source_locale': _locale,
      'education_level_id': _levelId,
      'subject_id': _subjectId,
      'chapter_id': _chapterId,
      'topic_id': _chapterId == null ? null : _topicId,
      'difficulty': _difficulty,
      'marks': _marks.text.trim(),
      'access_level': _access,
      'required_entitlement_key': entitled ? _entitlement.text.trim() : null,
      'translations': translations,
      'options': options,
    };
  }

  Future<void> _save() async {
    final valid = _form.currentState!.validate();
    final optionsOk = _correctCountValid();
    setState(() => _optionsInvalid = !optionsOk);
    if (!valid || !optionsOk) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = ObLocalizations.of(context);
    final repo = ref.read(adminQuestionRepositoryProvider);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    try {
      final saved = _creating
          ? await repo.createQuestion(_buildContent(), changeNote: note)
          : await repo.updateQuestion(_existing!.id, _buildContent(), changeNote: note);
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
                  ..._optionFields(l10n),
                  ..._classification(l10n),
                  ..._footer(l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
          _resetOptions();
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
          _resetOptions();
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
      decoration: InputDecoration(labelText: l10n.adminFieldStem, helperText: l10n.adminMathHint, helperMaxLines: 2),
      validator: (v) => _required(l10n, v),
    ),
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

  List<Widget> _optionFields(ObLocalizations l10n) {
    final max = _type == QuestionType.mcqMulti ? _maxMultiOptions : _maxSingleOptions;
    return [
      const SizedBox(height: AppSpacing.lg),
      Semantics(header: true, child: Text(l10n.adminOptionsHeading, style: Theme.of(context).textTheme.titleMedium)),
      for (final (i, o) in _options.indexed)
        Padding(
          key: ObjectKey(o),
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: TextFormField(
                  key: Key('option-label-$i'),
                  controller: o.label,
                  decoration: InputDecoration(labelText: l10n.adminOptionLabel),
                  validator: (v) => (v?.trim().isEmpty ?? true) || v!.trim().length > 8 ? l10n.errorValidation : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  key: Key('option-text-$i'),
                  controller: o.text,
                  decoration: InputDecoration(labelText: l10n.adminOptionText),
                  validator: (v) => _required(l10n, v),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Semantics(
                label: l10n.adminOptionCorrect,
                child: Checkbox(
                  key: Key('option-correct-$i'),
                  value: o.correct,
                  onChanged: (v) => _setCorrect(i, v ?? false),
                ),
              ),
              if (!_isTrueFalse)
                IconButton(
                  key: Key('option-remove-$i'),
                  tooltip: l10n.adminRemoveOption,
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _options.length <= _minOptions
                      ? null
                      : () => setState(() {
                          _options.removeAt(i).dispose();
                          _optionsInvalid = false;
                        }),
                ),
            ],
          ),
        ),
      if (_optionsInvalid)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _type == QuestionType.mcqMulti ? l10n.adminCorrectAtLeastOne : l10n.adminCorrectExactlyOne,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      if (!_isTrueFalse && _options.length < max)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('option-add'),
            icon: const Icon(Icons.add),
            label: Text(l10n.adminAddOption),
            onPressed: () => setState(
              () => _options.add(_OptionDraft(label: _labels[_locale]![_options.length], text: '')),
            ),
          ),
        ),
    ];
  }

  List<Widget> _classification(ObLocalizations l10n) {
    final locale = Localizations.localeOf(context).languageCode;
    final subjects = _subjects.where((s) => s.educationLevelId == _levelId).toList();
    final topics = _chapters.where((c) => c.id == _chapterId).expand((c) => c.topics).where((t) => t.isActive);
    DropdownButtonFormField<String?> picker(
      String key,
      String label,
      String? value,
      List<(String, String)> items,
      void Function(String?) onChanged, {
      bool requiredValue = false,
    }) => DropdownButtonFormField<String?>(
      key: Key(key),
      initialValue: items.any((e) => e.$1 == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (!requiredValue) DropdownMenuItem(value: null, child: Text(l10n.adminNoneOption)),
        for (final (id, name) in items) DropdownMenuItem(value: id, child: Text(name)),
      ],
      onChanged: onChanged,
      validator: requiredValue ? (v) => v == null ? l10n.errorValidation : null : null,
    );
    return [
      const SizedBox(height: AppSpacing.lg),
      picker(
        'question-level',
        l10n.adminLevel,
        _levelId,
        [for (final l in _levels) (l.id, l.name.resolve(locale))],
        (v) => setState(() {
          _levelId = v;
          _pickSubject(null);
        }),
        requiredValue: true,
      ),
      const SizedBox(height: AppSpacing.sm),
      picker(
        'question-subject',
        l10n.adminFieldSubject,
        _subjectId,
        [for (final s in subjects) (s.id, s.name.resolve(locale))],
        _pickSubject,
        requiredValue: true,
      ),
      const SizedBox(height: AppSpacing.sm),
      picker(
        'question-chapter',
        l10n.adminFieldChapter,
        _chapterId,
        [for (final c in _chapters.where((c) => c.isActive)) (c.id, '${c.number}. ${c.name.resolve(locale)}')],
        (v) => setState(() {
          _chapterId = v;
          _topicId = null;
        }),
      ),
      const SizedBox(height: AppSpacing.sm),
      picker(
        'question-topic',
        l10n.adminFieldTopic,
        _topicId,
        [for (final t in topics) (t.id, t.name.resolve(locale))],
        (v) => setState(() => _topicId = v),
      ),
    ];
  }

  List<Widget> _footer(ObLocalizations l10n) => [
    const SizedBox(height: AppSpacing.lg),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
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
