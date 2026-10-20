import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';

const _maxNameLength = 300;

/// Chapter or topic name in every locale the admin edits, plus the chapter number when asked for.
/// Field rules mirror the server (Bangla required, 300 characters); the server stays the authority.
Future<void> showNameDialog(
  BuildContext context, {
  required String title,
  required Future<void> Function(LocalizedText name, int? number) onSave,
  LocalizedText? initial,
  int? initialNumber,
  bool askNumber = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _NameDialog(
    title: title,
    onSave: onSave,
    initial: initial,
    initialNumber: initialNumber,
    askNumber: askNumber,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.onSave,
    required this.initial,
    required this.initialNumber,
    required this.askNumber,
  });

  final String title;
  final Future<void> Function(LocalizedText name, int? number) onSave;
  final LocalizedText? initial;
  final int? initialNumber;
  final bool askNumber;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _form = GlobalKey<FormState>();
  late final _bn = TextEditingController(text: widget.initial?.values['bn'] ?? '');
  late final _en = TextEditingController(text: widget.initial?.values['en'] ?? '');
  late final _number = TextEditingController(text: widget.initialNumber?.toString() ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _bn.dispose();
    _en.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final l10n = ObLocalizations.of(context);
    final name = LocalizedText({
      'bn': _bn.text.trim(),
      if (_en.text.trim().isNotEmpty) 'en': _en.text.trim(),
    });
    try {
      await widget.onSave(name, widget.askNumber ? int.parse(_number.text.trim()) : null);
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
    String? requiredText(String? v) {
      final text = v?.trim() ?? '';
      return text.isEmpty || text.length > _maxNameLength ? l10n.errorValidation : null;
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
                if (widget.askNumber) ...[
                  TextFormField(
                    key: const Key('name-dialog-number'),
                    controller: _number,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.adminChapterNumber),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      return n == null || n < 1 || n > 200 ? l10n.errorValidation : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('name-dialog-bn'),
                  controller: _bn,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.adminNameBangla),
                  validator: requiredText,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('name-dialog-en'),
                  controller: _en,
                  decoration: InputDecoration(labelText: l10n.adminNameEnglish),
                  validator: (v) => (v?.trim().length ?? 0) > _maxNameLength ? l10n.errorValidation : null,
                ),
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
        FilledButton(onPressed: _busy ? null : _submit, child: Text(l10n.actionSave)),
      ],
    );
  }
}
