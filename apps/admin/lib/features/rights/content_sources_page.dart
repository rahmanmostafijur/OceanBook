import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'rights_api.dart';
import 'rights_labels.dart';

final contentSourcesProvider = FutureProvider.autoDispose<List<ContentSource>>(
  (ref) => ref.watch(rightsRepositoryProvider).sources(),
);

/// Where content comes from (boards, publishers, authors, ...). Sources are retired, never deleted, so
/// existing provenance keeps pointing at them.
class ContentSourcesPage extends ConsumerWidget {
  const ContentSourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              key: const Key('new-source'),
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _NewSourceDialog()),
              icon: const Icon(Icons.add),
              label: Text(l10n.adminNewSource),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (ref.watch(contentSourcesProvider)) {
              AsyncData(:final value) when value.isEmpty => EmptyState(
                icon: Icons.source_outlined,
                title: l10n.adminNavContentSources,
              ),
              AsyncData(:final value) => Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(l10n.adminColumnName)),
                        DataColumn(label: Text(l10n.adminColumnKind)),
                        DataColumn(label: Text(l10n.adminColumnStatus)),
                        DataColumn(label: Text(l10n.adminColumnActive)),
                      ],
                      rows: [
                        for (final s in value)
                          DataRow(
                            cells: [
                              DataCell(Text(s.name.resolve(locale))),
                              DataCell(Text(sourceKindLabel(l10n, s.kind))),
                              DataCell(Text(s.isActive ? l10n.adminSourceActive : l10n.adminSourceRetired)),
                              DataCell(
                                Semantics(
                                  label: '${s.name.resolve(locale)}: ${l10n.adminColumnActive}',
                                  child: Switch(
                                    key: Key('source-active-${s.id}'),
                                    value: s.isActive,
                                    onChanged: (v) async {
                                      await ref.read(rightsRepositoryProvider).setSourceActive(s.id, isActive: v);
                                      ref.invalidate(contentSourcesProvider);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              AsyncError(:final error) => ErrorState(
                title: l10n.errorTitle,
                message: adminFailureMessage(l10n, error),
                retryLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(contentSourcesProvider),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

/// Owns its controllers so text fields outlive the closing animation safely.
class _NewSourceDialog extends ConsumerStatefulWidget {
  const _NewSourceDialog();

  @override
  ConsumerState<_NewSourceDialog> createState() => _NewSourceDialogState();
}

class _NewSourceDialogState extends ConsumerState<_NewSourceDialog> {
  final _form = GlobalKey<FormState>();
  final _nameBn = TextEditingController();
  final _nameEn = TextEditingController();
  final _website = TextEditingController();
  String _kind = 'publisher';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameBn.dispose();
    _nameEn.dispose();
    _website.dispose();
    super.dispose();
  }

  String? _urlError(ObLocalizations l10n, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty
        ? null
        : l10n.errorValidation;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final l10n = ObLocalizations.of(context);
    final name = {
      if (_nameBn.text.trim().isNotEmpty) 'bn': _nameBn.text.trim(),
      if (_nameEn.text.trim().isNotEmpty) 'en': _nameEn.text.trim(),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(rightsRepositoryProvider)
          .createSource(
            kind: _kind,
            name: name,
            websiteUrl: _website.text.trim().isEmpty ? null : _website.text.trim(),
          );
      ref.invalidate(contentSourcesProvider);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      setState(() {
        _busy = false;
        _error = adminFailureMessage(l10n, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminNewSource),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('new-source-name-bn'),
                controller: _nameBn,
                decoration: InputDecoration(labelText: '${l10n.adminColumnName} (${l10n.languageBangla})'),
                validator: (v) => (v ?? '').trim().isEmpty && _nameEn.text.trim().isEmpty ? l10n.errorValidation : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('new-source-name-en'),
                controller: _nameEn,
                decoration: InputDecoration(labelText: '${l10n.adminColumnName} (${l10n.languageEnglish})'),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: InputDecoration(labelText: l10n.adminColumnKind),
                items: [
                  for (final kind in sourceKinds)
                    DropdownMenuItem(value: kind, child: Text(sourceKindLabel(l10n, kind))),
                ],
                onChanged: (v) => setState(() => _kind = v ?? 'publisher'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                key: const Key('new-source-website'),
                controller: _website,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: l10n.adminWebsite),
                validator: (v) => _urlError(l10n, v),
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
          key: const Key('new-source-create'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.adminActionCreate),
        ),
      ],
    );
  }
}
