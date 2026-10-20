import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_curriculum_api.dart';

final _slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _keyPattern = RegExp(r'^[a-z][a-z0-9_]*$');
final _boardCodePattern = RegExp(r'^[0-9A-Za-z]{1,10}$');
const _maxNameLength = 300;

/// Creates a subject, or edits one when [subject] is given (curriculum, level and slug are fixed once
/// created). Field rules mirror the server for instant feedback; the server stays the authority.
Future<void> showSubjectDialog(BuildContext context, {CurriculumSubject? subject, VoidCallback? onSaved}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SubjectDialog(subject: subject, onSaved: onSaved),
    );

class _SubjectDialog extends ConsumerStatefulWidget {
  const _SubjectDialog({required this.subject, required this.onSaved});

  final CurriculumSubject? subject;
  final VoidCallback? onSaved;

  @override
  ConsumerState<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends ConsumerState<_SubjectDialog> {
  final _form = GlobalKey<FormState>();
  late final _slug = TextEditingController(text: widget.subject?.slug ?? '');
  late final _family = TextEditingController(text: widget.subject?.familyKey ?? '');
  late final _bn = TextEditingController(text: widget.subject?.name.values['bn'] ?? '');
  late final _en = TextEditingController(text: widget.subject?.name.values['en'] ?? '');
  late final _board = TextEditingController(text: widget.subject?.boardCode ?? '');
  late int? _paper = widget.subject?.paperNumber;
  late String? _curriculumId = widget.subject?.curriculumId;
  late String? _levelId = widget.subject?.educationLevelId;
  List<CurriculumOption> _curricula = const [];
  List<CurriculumOption> _levels = const [];
  List<CurriculumOption> _groups = const [];
  late final Map<String, String> _offerings = {
    for (final g in widget.subject?.groups ?? const <SubjectGroupLink>[]) g.groupId: g.offering,
  };
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _creating => widget.subject == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_slug, _family, _bn, _en, _board]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(adminCurriculumRepositoryProvider);
    try {
      if (_creating) {
        final results = await Future.wait([repo.curricula(), repo.levels()]);
        _curricula = results[0];
        _levels = results[1];
      }
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
      _groups = const [];
      _offerings.clear();
    });
    if (id == null) return;
    try {
      final groups = await ref.read(adminCurriculumRepositoryProvider).groups(id);
      if (mounted && _levelId == id) setState(() => _groups = groups);
    } on Object catch (error) {
      if (mounted) setState(() => _error = adminFailureMessage(ObLocalizations.of(context), error));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = ObLocalizations.of(context);
    final fields = SubjectFields(
      familyKey: _family.text.trim(),
      name: LocalizedText({'bn': _bn.text.trim(), if (_en.text.trim().isNotEmpty) 'en': _en.text.trim()}),
      boardCode: _board.text.trim().isEmpty ? null : _board.text.trim(),
      paperNumber: _paper,
      groups: [for (final e in _offerings.entries) SubjectGroupLink(groupId: e.key, offering: e.value)],
    );
    final repo = ref.read(adminCurriculumRepositoryProvider);
    try {
      if (_creating) {
        await repo.createSubject(
          curriculumId: _curriculumId!,
          levelId: _levelId!,
          slug: _slug.text.trim(),
          fields: fields,
        );
      } else {
        await repo.updateSubject(widget.subject!.id, fields: fields);
      }
      widget.onSaved?.call();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = adminFailureMessage(l10n, error);
      });
    }
  }

  String _offeringLabel(ObLocalizations l10n, String? offering) => switch (offering) {
    'compulsory' => l10n.adminOfferingCompulsory,
    'elective' => l10n.adminOfferingElective,
    'optional' => l10n.adminOfferingOptional,
    _ => l10n.adminOfferingNone,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    String? required(String? v) => (v?.trim().isEmpty ?? true) ? l10n.errorValidation : null;

    Widget gap() => const SizedBox(height: AppSpacing.sm);
    Widget picker(
      String keyName,
      String label,
      String? value,
      List<CurriculumOption> options,
      void Function(String?) onChanged,
    ) => DropdownButtonFormField<String>(
      key: Key(keyName),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.name.resolve(locale)))],
      onChanged: onChanged,
      validator: (v) => v == null ? l10n.errorValidation : null,
    );

    return AlertDialog(
      title: Text(_creating ? l10n.adminAddSubject : l10n.adminEditSubject),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: _loading
            ? PageLoading.linear(semanticLabel: l10n.commonLoading)
            : Form(
                key: _form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_creating) ...[
                        picker(
                          'subject-curriculum',
                          l10n.adminCurriculum,
                          _curriculumId,
                          _curricula,
                          (v) => setState(() => _curriculumId = v),
                        ),
                        gap(),
                        picker('subject-level', l10n.adminLevel, _levelId, _levels, _pickLevel),
                        gap(),
                        TextFormField(
                          key: const Key('subject-slug'),
                          controller: _slug,
                          decoration: InputDecoration(labelText: l10n.adminColumnSlug),
                          validator: (v) => _slugPattern.hasMatch(v?.trim() ?? '') && v!.trim().length <= 120
                              ? null
                              : l10n.errorValidation,
                        ),
                        gap(),
                      ],
                      TextFormField(
                        key: const Key('subject-bn'),
                        controller: _bn,
                        decoration: InputDecoration(labelText: l10n.adminNameBangla),
                        validator: (v) =>
                            required(v) ?? ((v!.trim().length > _maxNameLength) ? l10n.errorValidation : null),
                      ),
                      gap(),
                      TextFormField(
                        key: const Key('subject-en'),
                        controller: _en,
                        decoration: InputDecoration(labelText: l10n.adminNameEnglish),
                        validator: (v) => (v?.trim().length ?? 0) > _maxNameLength ? l10n.errorValidation : null,
                      ),
                      gap(),
                      TextFormField(
                        key: const Key('subject-family'),
                        controller: _family,
                        decoration: InputDecoration(labelText: l10n.adminFamilyKey),
                        validator: (v) => _keyPattern.hasMatch(v?.trim() ?? '') && v!.trim().length <= 60
                            ? null
                            : l10n.errorValidation,
                      ),
                      gap(),
                      TextFormField(
                        key: const Key('subject-board'),
                        controller: _board,
                        decoration: InputDecoration(labelText: l10n.adminBoardCode),
                        validator: (v) {
                          final text = v?.trim() ?? '';
                          return text.isEmpty || _boardCodePattern.hasMatch(text) ? null : l10n.errorValidation;
                        },
                      ),
                      gap(),
                      DropdownButtonFormField<int?>(
                        key: const Key('subject-paper'),
                        initialValue: _paper,
                        decoration: InputDecoration(labelText: l10n.adminPaperNumber),
                        items: [
                          DropdownMenuItem(value: null, child: Text(l10n.adminPaperNone)),
                          DropdownMenuItem(value: 1, child: Text(l10n.adminPaperFirst)),
                          DropdownMenuItem(value: 2, child: Text(l10n.adminPaperSecond)),
                        ],
                        onChanged: (v) => setState(() => _paper = v),
                      ),
                      if (_groups.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(l10n.adminGroupsHeading, style: Theme.of(context).textTheme.titleSmall),
                        for (final group in _groups) ...[
                          gap(),
                          DropdownButtonFormField<String?>(
                            key: Key('subject-group-${group.key}'),
                            initialValue: _offerings[group.id],
                            decoration: InputDecoration(labelText: group.name.resolve(locale)),
                            items: [
                              for (final o in [null, ...offerings])
                                DropdownMenuItem(value: o, child: Text(_offeringLabel(l10n, o))),
                            ],
                            onChanged: (v) => setState(() {
                              if (v == null) {
                                _offerings.remove(group.id);
                              } else {
                                _offerings[group.id] = v;
                              }
                            }),
                          ),
                        ],
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(onPressed: _busy || _loading ? null : _submit, child: Text(l10n.actionSave)),
      ],
    );
  }
}
