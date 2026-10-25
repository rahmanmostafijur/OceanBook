import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'academic_setup_api.dart';

const _maxNameLength = 300;
const _maxKeyLength = 60;
const _firstYear = 1990;
const _lastYear = 2100;
const _maxPosition = 10000;
final _keyPattern = RegExp(r'^[a-z][a-z0-9_]*$');

String boardTypeLabel(ObLocalizations l10n, String type) => switch (type) {
  'general' => l10n.adminSetupBoardGeneral,
  'madrasah' => l10n.adminSetupBoardMadrasah,
  'technical' => l10n.adminSetupBoardTechnical,
  _ => type,
};

/// Creates a level, group, curriculum, board or medium, or edits [entry]. The key is chosen once and cannot
/// change. Field rules mirror the server (Bangla name required, years 1990 to 2100); the server stays the
/// authority.
Future<void> showSetupDialog(
  BuildContext context, {
  required SetupKind kind,
  required String title,
  required Future<void> Function(String key, SetupFields fields) onSave,
  SetupEntry? entry,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SetupDialog(kind: kind, title: title, onSave: onSave, entry: entry),
);

class _SetupDialog extends StatefulWidget {
  const _SetupDialog({required this.kind, required this.title, required this.onSave, required this.entry});

  final SetupKind kind;
  final String title;
  final Future<void> Function(String key, SetupFields fields) onSave;
  final SetupEntry? entry;

  @override
  State<_SetupDialog> createState() => _SetupDialogState();
}

class _SetupDialogState extends State<_SetupDialog> {
  final _form = GlobalKey<FormState>();
  late final _key = TextEditingController(text: widget.entry?.key ?? '');
  late final _bn = TextEditingController(text: widget.entry?.name.values['bn'] ?? '');
  late final _en = TextEditingController(text: widget.entry?.name.values['en'] ?? '');
  late final _position = TextEditingController(text: '${widget.entry?.position ?? 0}');
  late final _from = TextEditingController(text: widget.entry?.effectiveFromYear?.toString() ?? '');
  late final _to = TextEditingController(text: widget.entry?.effectiveToYear?.toString() ?? '');
  late String _boardType = widget.entry?.boardType ?? boardTypes.first;
  late String _contentLocale = widget.entry?.contentLocale ?? contentLocales.first;
  late bool _isCurrent = widget.entry?.isCurrent ?? false;
  bool _busy = false;
  String? _error;

  bool get _creating => widget.entry == null;

  @override
  void dispose() {
    for (final c in [_key, _bn, _en, _position, _from, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _year(TextEditingController c) => c.text.trim().isEmpty ? null : int.parse(c.text.trim());

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = ObLocalizations.of(context);
    final fields = SetupFields(
      name: LocalizedText({'bn': _bn.text.trim(), if (_en.text.trim().isNotEmpty) 'en': _en.text.trim()}),
      position: int.tryParse(_position.text.trim()) ?? 0,
      boardType: _boardType,
      contentLocale: _contentLocale,
      effectiveFromYear: _year(_from),
      effectiveToYear: _year(_to),
      isCurrent: _isCurrent,
    );
    try {
      await widget.onSave(_key.text.trim(), fields);
      if (mounted) Navigator.of(context).pop();
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
    String? nameRule(String? v, {required bool required}) {
      final text = v?.trim() ?? '';
      return (required && text.isEmpty) || text.length > _maxNameLength ? l10n.errorValidation : null;
    }

    String? yearRule(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final year = int.tryParse(v.trim());
      return year == null || year < _firstYear || year > _lastYear ? l10n.errorValidation : null;
    }

    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_creating) ...[
                  TextFormField(
                    key: const Key('setup-key'),
                    controller: _key,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.adminSetupKey,
                      helperText: l10n.adminSetupKeyHint,
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      final text = v?.trim() ?? '';
                      return text.length > _maxKeyLength || !_keyPattern.hasMatch(text) ? l10n.errorValidation : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('setup-bn'),
                  controller: _bn,
                  autofocus: !_creating,
                  decoration: InputDecoration(labelText: l10n.adminNameBangla),
                  validator: (v) => nameRule(v, required: true),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('setup-en'),
                  controller: _en,
                  decoration: InputDecoration(labelText: l10n.adminNameEnglish),
                  validator: (v) => nameRule(v, required: false),
                ),
                ..._kindFields(l10n, yearRule),
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
        FilledButton(key: const Key('setup-save'), onPressed: _busy ? null : _submit, child: Text(l10n.actionSave)),
      ],
    );
  }

  List<Widget> _kindFields(ObLocalizations l10n, String? Function(String?) yearRule) {
    const gap = SizedBox(height: AppSpacing.sm);
    switch (widget.kind) {
      case SetupKind.levels:
        return [
          gap,
          TextFormField(
            key: const Key('setup-position'),
            controller: _position,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.adminSetupPosition),
            validator: (v) {
              final n = int.tryParse(v?.trim() ?? '');
              return n == null || n < 0 || n > _maxPosition ? l10n.errorValidation : null;
            },
          ),
        ];
      case SetupKind.groups:
        return const [];
      case SetupKind.curricula:
        return [
          gap,
          TextFormField(
            key: const Key('setup-from'),
            controller: _from,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.adminSetupYearFrom),
            validator: yearRule,
          ),
          gap,
          TextFormField(
            key: const Key('setup-to'),
            controller: _to,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.adminSetupYearTo),
            validator: (v) {
              final error = yearRule(v);
              final from = int.tryParse(_from.text.trim());
              final to = int.tryParse(v?.trim() ?? '');
              return error ?? (from != null && to != null && to < from ? l10n.errorValidation : null);
            },
          ),
          CheckboxListTile(
            key: const Key('setup-current'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.adminSetupIsCurrent),
            value: _isCurrent,
            onChanged: (v) => setState(() => _isCurrent = v ?? false),
          ),
        ];
      case SetupKind.boards:
        return [
          gap,
          DropdownButtonFormField<String>(
            key: const Key('setup-board-type'),
            isExpanded: true,
            initialValue: _boardType,
            decoration: InputDecoration(labelText: l10n.adminSetupBoardType),
            items: [
              for (final t in boardTypes) DropdownMenuItem(value: t, child: Text(boardTypeLabel(l10n, t))),
            ],
            onChanged: (v) => setState(() => _boardType = v!),
          ),
        ];
      case SetupKind.media:
        return [
          gap,
          DropdownButtonFormField<String>(
            key: const Key('setup-content-locale'),
            isExpanded: true,
            initialValue: _contentLocale,
            decoration: InputDecoration(labelText: l10n.adminSetupContentLocale),
            items: [
              DropdownMenuItem(value: 'bn', child: Text(l10n.adminLanguageBangla)),
              DropdownMenuItem(value: 'en', child: Text(l10n.adminLanguageEnglish)),
            ],
            onChanged: (v) => setState(() => _contentLocale = v!),
          ),
        ];
    }
  }
}
