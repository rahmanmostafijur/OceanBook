import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failure_messages.dart';
import '../../data/library_providers.dart';

const int _nameMaxLength = 80;
const int _descriptionMaxLength = 280;

/// Create a shelf, or edit [existing]. Returns the created shelf (null when cancelled or edited).
Future<BookCollection?> showShelfEditor(BuildContext context, {BookCollection? existing}) =>
    showDialog<BookCollection?>(
      context: context,
      builder: (_) => _ShelfEditor(existing: existing),
    );

/// Asks before a destructive action. Resolves to true only when the user confirms.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final l10n = ObLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.actionCancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ShelfEditor extends ConsumerStatefulWidget {
  const _ShelfEditor({this.existing});

  final BookCollection? existing;

  @override
  ConsumerState<_ShelfEditor> createState() => _ShelfEditorState();
}

class _ShelfEditorState extends ConsumerState<_ShelfEditor> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _description = TextEditingController(text: widget.existing?.description);
  final _formKey = GlobalKey<FormState>();

  /// One id per form, so pressing Create again after a lost response cannot make a second shelf.
  final _newId = const Uuid().v7();
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _serverError = null;
    });
    final controller = ref.read(collectionsProvider.notifier);
    final name = _name.text.trim();
    try {
      final existing = widget.existing;
      if (existing == null) {
        final created = await controller.create(
          id: _newId,
          name: name,
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        );
        if (mounted) Navigator.of(context).pop(created);
      } else {
        await controller.edit(existing.id, name: name, description: _description.text);
        if (mounted) Navigator.of(context).pop();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError = failureMessage(ObLocalizations.of(context), error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? l10n.shelvesNew : l10n.shelfEdit),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  maxLength: _nameMaxLength,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.shelfName, errorText: _serverError),
                  validator: (value) => (value ?? '').trim().isEmpty ? l10n.shelfNameRequired : null,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _description,
                  maxLength: _descriptionMaxLength,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: l10n.shelfDescription),
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(widget.existing == null ? l10n.shelfCreate : l10n.shelfSave),
        ),
      ],
    );
  }
}
