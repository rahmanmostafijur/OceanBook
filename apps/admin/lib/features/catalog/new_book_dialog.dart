import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_catalog_api.dart';
import 'books_page.dart';

final _slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Creates a draft book (source-language title, slug, access level). Field rules mirror the server for
/// instant feedback; the server's validation is still the authority.
Future<void> showNewBookDialog(BuildContext context, WidgetRef ref) =>
    showDialog<void>(context: context, builder: (_) => const _NewBookDialog());

class _NewBookDialog extends ConsumerStatefulWidget {
  const _NewBookDialog();

  @override
  ConsumerState<_NewBookDialog> createState() => _NewBookDialogState();
}

class _NewBookDialogState extends ConsumerState<_NewBookDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _slug = TextEditingController();
  String _locale = 'bn';
  String _access = 'entitled';
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _title.dispose();
    _slug.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });
    final l10n = ObLocalizations.of(context);
    try {
      final book = await ref
          .read(adminCatalogRepositoryProvider)
          .createBook(slug: _slug.text.trim(), sourceLocale: _locale, title: _title.text.trim(), accessLevel: _access);
      ref.invalidate(adminBooksProvider);
      if (!mounted) return;
      final router = GoRouter.of(context); // captured before the dialog's context goes away
      Navigator.of(context).pop();
      router.go('/books/${book.id}');
    } on Object catch (error) {
      setState(() {
        _busy = false;
        _error = adminFailureMessage(l10n, error);
        _fieldErrors = error is ServerFailure ? error.fieldErrors : const {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminNewBook),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('new-book-title'),
                controller: _title,
                decoration: InputDecoration(labelText: l10n.adminColumnTitle),
                validator: (v) => (v == null || v.trim().isEmpty) ? l10n.errorValidation : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('new-book-slug'),
                controller: _slug,
                decoration: InputDecoration(labelText: l10n.adminColumnSlug, errorText: _fieldErrors['slug']),
                validator: (v) => _slugPattern.hasMatch(v?.trim() ?? '') ? null : l10n.errorValidation,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _locale,
                decoration: InputDecoration(labelText: l10n.adminSourceLanguage),
                items: [
                  DropdownMenuItem(value: 'bn', child: Text(l10n.languageBangla)),
                  DropdownMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
                ],
                onChanged: (v) => setState(() => _locale = v ?? 'bn'),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _access,
                decoration: InputDecoration(labelText: l10n.adminColumnAccess),
                items: [
                  for (final level in const ['free', 'registered', 'entitled'])
                    DropdownMenuItem(value: level, child: Text(accessLabel(l10n, level))),
                ],
                onChanged: (v) => setState(() => _access = v ?? 'entitled'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(
          key: const Key('new-book-create'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminActionCreate),
        ),
      ],
    );
  }
}
