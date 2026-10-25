import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../academics/admin_curriculum_api.dart';
import 'admin_question_api.dart';
import 'creative_parts.dart' show formatMarks;
import 'paper_detail_page.dart' show adminPaperProvider;
import 'papers_page.dart' show adminPapersProvider;
import 'question_labels.dart';

const examKinds = ['board_final', 'test', 'pre_test', 'model', 'admission'];
const paperSections = ['full', 'mcq', 'cq'];
const _firstExamYear = 1990;
const _lastExamYear = 2100;
const _maxBoards = 12;
const _fieldWidth = 220.0;

String paperSectionLabel(ObLocalizations l10n, String section) => switch (section) {
  'full' => l10n.adminSectionFull,
  'mcq' => l10n.adminSectionMcq,
  'cq' => l10n.adminSectionCq,
  _ => section,
};

/// Creates a question paper, or edits a draft one when [paperId] is given. Level and subject are fixed
/// once a paper exists (the server does not allow changing them), so the edit form leaves them out.
class PaperEditorPage extends ConsumerWidget {
  const PaperEditorPage({this.paperId, super.key});

  final String? paperId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final id = paperId;
    if (id == null) return const _PaperForm();
    return switch (ref.watch(adminPaperProvider(id))) {
      AsyncValue(:final value?) when value.status != 'draft' => EmptyState(
        icon: Icons.edit_off_outlined,
        title: l10n.adminEditPaper,
        message: l10n.adminPaperLocked,
      ),
      AsyncValue(:final value?) => _PaperForm(paper: value),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminPaperProvider(id)),
      ),
      _ => PageLoading(semanticLabel: l10n.commonLoading),
    };
  }
}

class _PaperForm extends ConsumerStatefulWidget {
  const _PaperForm({this.paper});

  final AdminPaper? paper;

  @override
  ConsumerState<_PaperForm> createState() => _PaperFormState();
}

class _PaperFormState extends ConsumerState<_PaperForm> {
  final _form = GlobalKey<FormState>();
  final _year = TextEditingController();
  final _title = TextEditingController();
  final _marks = TextEditingController();
  final _duration = TextEditingController();
  final _entitlement = TextEditingController();
  String _kind = examKinds.first;
  String _section = paperSections.first;
  String _access = 'free';
  String? _levelId;
  String? _subjectId;
  String? _groupId;
  String? _mediumId;
  final Set<String> _boardIds = {};
  List<CurriculumOption> _levels = const [];
  List<CurriculumSubject> _subjects = const [];
  List<CurriculumOption> _groups = const [];
  List<CurriculumOption> _boards = const [];
  List<CurriculumOption> _media = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  AdminPaper? get _existing => widget.paper;
  bool get _creating => _existing == null;

  @override
  void initState() {
    super.initState();
    final p = _existing;
    if (p != null) {
      _year.text = '${p.examYear}';
      _title.text = p.title ?? '';
      _marks.text = p.totalMarks == null ? '' : formatMarks(p.totalMarks!);
      _duration.text = p.durationMinutes == null ? '' : '${p.durationMinutes}';
      _entitlement.text = p.requiredEntitlementKey ?? '';
      _kind = p.examKind;
      _section = p.section;
      _access = p.accessLevel;
      _levelId = p.educationLevelId;
      _subjectId = p.subjectId;
      _groupId = p.academicGroupId;
      _mediumId = p.instructionMediumId;
      _boardIds.addAll(p.boardIds);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_year, _title, _marks, _duration, _entitlement]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(adminCurriculumRepositoryProvider);
    try {
      final results = await Future.wait([repo.levels(), repo.subjects(), repo.boards(), repo.instructionMedia()]);
      _levels = results[0] as List<CurriculumOption>;
      _subjects = results[1] as List<CurriculumSubject>;
      _boards = results[2] as List<CurriculumOption>;
      _media = results[3] as List<CurriculumOption>;
      if (_levelId != null) _groups = await repo.groups(_levelId!);
      if (mounted) setState(() => _loading = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = adminFailureMessage(ObLocalizations.of(context), error);
      });
    }
  }

  Future<void> _pickLevel(String? id) async {
    setState(() {
      _levelId = id;
      _subjectId = null;
      _groupId = null;
      _groups = const [];
    });
    if (id == null) return;
    try {
      final groups = await ref.read(adminCurriculumRepositoryProvider).groups(id);
      if (mounted && _levelId == id) setState(() => _groups = groups);
    } on Object catch (error) {
      if (mounted) setState(() => _error = adminFailureMessage(ObLocalizations.of(context), error));
    }
  }

  String? _optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, Object?> _body() {
    final entitled = _access == 'entitled';
    return {
      if (_creating) 'education_level_id': _levelId,
      if (_creating) 'subject_id': _subjectId,
      'academic_group_id': _groupId,
      'instruction_medium_id': _mediumId,
      'exam_year': int.parse(_year.text.trim()),
      'exam_kind': _kind,
      'section': _section,
      'title': _optional(_title),
      'total_marks': _optional(_marks),
      'duration_minutes': _optional(_duration) == null ? null : int.parse(_duration.text.trim()),
      'board_ids': _boardIds.toList(),
      'access_level': _access,
      'required_entitlement_key': entitled ? _entitlement.text.trim() : null,
    };
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = ObLocalizations.of(context);
    final repo = ref.read(adminQuestionRepositoryProvider);
    try {
      final saved = _creating ? await repo.createPaper(_body()) : await repo.updatePaper(_existing!.id, _body());
      ref
        ..invalidate(adminPapersProvider)
        ..invalidate(adminPaperProvider(saved.id));
      if (mounted) context.go('/question-papers/${saved.id}');
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
                      _creating ? l10n.adminNewPaper : l10n.adminEditPaper,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ..._classification(l10n),
                  ..._details(l10n),
                  ..._boardChips(l10n),
                  ..._footer(l10n),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  DropdownButtonFormField<String?> _picker(
    ObLocalizations l10n,
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

  List<Widget> _classification(ObLocalizations l10n) {
    final locale = Localizations.localeOf(context).languageCode;
    final subjects = _subjects.where((s) => s.educationLevelId == _levelId).toList();
    return [
      if (_creating) ...[
        _picker(
          l10n,
          'paper-level',
          l10n.adminLevel,
          _levelId,
          [for (final l in _levels) (l.id, l.name.resolve(locale))],
          _pickLevel,
          requiredValue: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        _picker(
          l10n,
          'paper-subject',
          l10n.adminFieldSubject,
          _subjectId,
          [for (final s in subjects) (s.id, s.name.resolve(locale))],
          (v) => setState(() => _subjectId = v),
          requiredValue: true,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      _picker(l10n, 'paper-group', l10n.adminFieldGroup, _groupId, [
        for (final g in _groups) (g.id, g.name.resolve(locale)),
      ], (v) => setState(() => _groupId = v)),
      const SizedBox(height: AppSpacing.sm),
      _picker(l10n, 'paper-medium', l10n.adminFieldMedium, _mediumId, [
        for (final m in _media) (m.id, m.name.resolve(locale)),
      ], (v) => setState(() => _mediumId = v)),
    ];
  }

  List<Widget> _details(ObLocalizations l10n) => [
    const SizedBox(height: AppSpacing.lg),
    Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: _fieldWidth,
          child: TextFormField(
            key: const Key('paper-year'),
            controller: _year,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.adminFieldExamYear),
            validator: (v) {
              final year = int.tryParse(v?.trim() ?? '');
              return year == null || year < _firstExamYear || year > _lastExamYear ? l10n.errorValidation : null;
            },
          ),
        ),
        SizedBox(
          width: _fieldWidth,
          child: DropdownButtonFormField<String>(
            key: const Key('paper-kind'),
            isExpanded: true,
            initialValue: _kind,
            decoration: InputDecoration(labelText: l10n.adminFieldExamKind),
            items: [for (final k in examKinds) DropdownMenuItem(value: k, child: Text(examKindLabel(l10n, k)))],
            onChanged: (v) => setState(() => _kind = v!),
          ),
        ),
        SizedBox(
          width: _fieldWidth,
          child: DropdownButtonFormField<String>(
            key: const Key('paper-section'),
            isExpanded: true,
            initialValue: _section,
            decoration: InputDecoration(labelText: l10n.adminFieldSection),
            items: [
              for (final s in paperSections) DropdownMenuItem(value: s, child: Text(paperSectionLabel(l10n, s))),
            ],
            onChanged: (v) => setState(() => _section = v!),
          ),
        ),
        SizedBox(
          width: _fieldWidth,
          child: TextFormField(
            key: const Key('paper-marks'),
            controller: _marks,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: l10n.adminFieldPaperMarks),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final marks = double.tryParse(v.trim());
              return marks == null || marks <= 0 || marks > 9999 ? l10n.errorValidation : null;
            },
          ),
        ),
        SizedBox(
          width: _fieldWidth,
          child: TextFormField(
            key: const Key('paper-duration'),
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.adminFieldDuration),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final minutes = int.tryParse(v.trim());
              return minutes == null || minutes < 1 || minutes > 1440 ? l10n.errorValidation : null;
            },
          ),
        ),
        SizedBox(
          width: _fieldWidth,
          child: DropdownButtonFormField<String>(
            key: const Key('paper-access'),
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
    const SizedBox(height: AppSpacing.sm),
    TextFormField(
      key: const Key('paper-title'),
      controller: _title,
      maxLength: 200,
      decoration: InputDecoration(labelText: l10n.adminFieldPaperTitle),
    ),
    if (_access == 'entitled')
      TextFormField(
        key: const Key('paper-entitlement'),
        controller: _entitlement,
        decoration: InputDecoration(labelText: l10n.adminEntitlementKey),
        validator: (v) => (v?.trim().isEmpty ?? true) ? l10n.errorValidation : null,
      ),
  ];

  List<Widget> _boardChips(ObLocalizations l10n) {
    final locale = Localizations.localeOf(context).languageCode;
    return [
      const SizedBox(height: AppSpacing.lg),
      Semantics(header: true, child: Text(l10n.adminFieldBoards, style: Theme.of(context).textTheme.titleMedium)),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final board in _boards)
            FilterChip(
              key: Key('paper-board-${board.key}'),
              label: Text(board.name.resolve(locale)),
              selected: _boardIds.contains(board.id),
              onSelected: (on) => setState(() {
                if (!on) {
                  _boardIds.remove(board.id);
                } else if (_boardIds.length < _maxBoards) {
                  _boardIds.add(board.id);
                }
              }),
            ),
        ],
      ),
    ];
  }

  List<Widget> _footer(ObLocalizations l10n) => [
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
          onPressed: _busy
              ? null
              : () => context.go(_creating ? '/question-papers' : '/question-papers/${_existing!.id}'),
          child: Text(l10n.actionCancel),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(key: const Key('paper-save'), onPressed: _busy ? null : _save, child: Text(l10n.actionSave)),
      ],
    ),
  ];
}
