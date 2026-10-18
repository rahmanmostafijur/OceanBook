import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../catalog/book_detail_page.dart';
import 'content_sources_page.dart';
import 'rights_api.dart';
import 'rights_labels.dart';

final editionProvenanceProvider = FutureProvider.autoDispose.family<List<ProvenanceRecord>, String>(
  (ref, editionId) => ref.watch(rightsRepositoryProvider).forEdition(editionId),
);

final _territoryPattern = RegExp(r'^([A-Z]{2}|\*)$');

/// Provenance records of one edition: record a new one, submit a draft for a second person, or narrow a
/// verified record. Which actions apply follows the record's state; the server re-checks every one.
class EditionRights extends ConsumerStatefulWidget {
  const EditionRights({required this.bookId, required this.editionId, super.key});

  final String bookId;
  final String editionId;

  @override
  ConsumerState<EditionRights> createState() => _EditionRightsState();
}

class _EditionRightsState extends ConsumerState<EditionRights> {
  String? _error;

  void _refresh() => ref
    ..invalidate(editionProvenanceProvider(widget.editionId))
    ..invalidate(adminBookProvider(widget.bookId));

  Future<void> _guard(Future<void> Function() action) async {
    final l10n = ObLocalizations.of(context);
    setState(() => _error = null);
    try {
      await action();
      _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = adminFailureMessage(l10n, error));
    }
  }

  Future<void> _record() async {
    final draft = await showDialog<NewProvenance>(context: context, builder: (_) => const _RecordDialog());
    if (draft == null) return;
    await _guard(() => ref.read(rightsRepositoryProvider).record(widget.editionId, draft));
  }

  Future<void> _narrow(ProvenanceRecord record) async {
    final change = await showDialog<(String, String)>(context: context, builder: (_) => const _NarrowDialog());
    if (change == null) return;
    await _guard(
      () => ref.read(rightsRepositoryProvider).narrow(record.id, rightsStatus: change.$1, reason: change.$2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final sources = {
      for (final s in ref.watch(contentSourcesProvider).value ?? const <ContentSource>[]) s.id: s.name.resolve(locale),
    };
    final records = ref.watch(editionProvenanceProvider(widget.editionId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.adminProvenance, style: theme.textTheme.titleSmall)),
            TextButton.icon(
              key: Key('record-${widget.editionId}'),
              onPressed: _record,
              icon: const Icon(Icons.add, size: AppSizes.iconSmall),
              label: Text(l10n.adminRecordProvenance),
            ),
          ],
        ),
        if (_error != null)
          Text(
            _error!,
            key: const Key('rights-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        switch (records) {
          AsyncData(:final value) when value.isEmpty => Text(l10n.adminGateNoProvenance),
          AsyncData(:final value) => Column(
            children: [
              for (final r in value)
                ListTile(
                  key: Key('prov-${r.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${sources[r.sourceId] ?? r.sourceId} · ${licenseLabel(l10n, r.licenseType)}'),
                  subtitle: Text(
                    '${rightsLabel(l10n, r.rightsStatus)} · ${verificationLabel(l10n, r.verificationStatus)}'
                    '${r.verificationNotes == null ? '' : '\n${r.verificationNotes}'}',
                  ),
                  trailing: r.isEditable
                      ? OutlinedButton(
                          key: Key('submit-prov-${r.id}'),
                          onPressed: () => _guard(() => ref.read(rightsRepositoryProvider).submit(r.id)),
                          child: Text(l10n.adminActionSubmit),
                        )
                      : r.isVerified
                      ? OutlinedButton(
                          key: Key('narrow-${r.id}'),
                          onPressed: () => _narrow(r),
                          child: Text(l10n.adminChangeRights),
                        )
                      : null,
                ),
            ],
          ),
          AsyncError(:final error) => Text(adminFailureMessage(l10n, error)),
          _ => PageLoading.linear(semanticLabel: ObLocalizations.of(context).commonLoading),
        },
      ],
    );
  }
}

class _RecordDialog extends ConsumerStatefulWidget {
  const _RecordDialog();

  @override
  ConsumerState<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends ConsumerState<_RecordDialog> {
  final _form = GlobalKey<FormState>();
  final _territories = TextEditingController(text: 'BD');
  final _reference = TextEditingController();
  String? _sourceId;
  String _license = 'licensed_commercial';
  String _rights = 'pending';

  @override
  void dispose() {
    _territories.dispose();
    _reference.dispose();
    super.dispose();
  }

  List<String> get _territoryList => [
    for (final t in _territories.text.split(RegExp(r'[,\s]+')))
      if (t.isNotEmpty) t.toUpperCase(),
  ];

  void _confirm() {
    if (!_form.currentState!.validate()) return;
    final reference = _reference.text.trim();
    Navigator.of(context).pop(
      NewProvenance(
        sourceId: _sourceId!,
        licenseType: _license,
        rightsStatus: _rights,
        territories: _territoryList.toSet().toList(),
        licenseReference: reference.isEmpty ? null : reference,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final sources = [
      for (final s in ref.watch(contentSourcesProvider).value ?? const <ContentSource>[])
        if (s.isActive) s,
    ];
    return AlertDialog(
      title: Text(l10n.adminRecordProvenance),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizes.maxFormWidth),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('record-source'),
                  decoration: InputDecoration(labelText: l10n.adminNavContentSources),
                  items: [for (final s in sources) DropdownMenuItem(value: s.id, child: Text(s.name.resolve(locale)))],
                  onChanged: (v) => setState(() => _sourceId = v),
                  validator: (v) => v == null ? l10n.errorValidation : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _license,
                  decoration: InputDecoration(labelText: l10n.adminLicense),
                  items: [
                    for (final t in licenseTypes) DropdownMenuItem(value: t, child: Text(licenseLabel(l10n, t))),
                  ],
                  onChanged: (v) => setState(() => _license = v ?? _license),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: _rights,
                  decoration: InputDecoration(labelText: l10n.adminRights),
                  items: [
                    for (final s in rightsStatuses) DropdownMenuItem(value: s, child: Text(rightsLabel(l10n, s))),
                  ],
                  onChanged: (v) => setState(() => _rights = v ?? _rights),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('record-territories'),
                  controller: _territories,
                  decoration: InputDecoration(labelText: l10n.adminTerritories, helperText: l10n.adminTerritoriesHint),
                  validator: (_) {
                    final list = _territoryList;
                    final ok = list.isNotEmpty && list.every(_territoryPattern.hasMatch);
                    return ok && (!list.contains('*') || list.length == 1) ? null : l10n.errorValidation;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('record-reference'),
                  controller: _reference,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: l10n.adminLicenseReference),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(key: const Key('record-confirm'), onPressed: _confirm, child: Text(l10n.adminActionCreate)),
      ],
    );
  }
}

/// Narrowing is immediate and can unpublish content, so it always asks for an audited reason.
class _NarrowDialog extends StatefulWidget {
  const _NarrowDialog();

  @override
  State<_NarrowDialog> createState() => _NarrowDialogState();
}

class _NarrowDialogState extends State<_NarrowDialog> {
  final _reason = TextEditingController();
  String _status = narrowingRights.first;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _reason.text.trim();
    if (text.length >= 3) Navigator.of(context).pop((_status, text)); // the server requires 3..500 characters
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminChangeRights),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.adminChangeRightsWarning),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            key: const Key('narrow-status'),
            initialValue: _status,
            decoration: InputDecoration(labelText: l10n.adminRights),
            items: [
              for (final s in narrowingRights) DropdownMenuItem(value: s, child: Text(rightsLabel(l10n, s))),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('narrow-reason'),
            controller: _reason,
            maxLength: 500,
            decoration: InputDecoration(labelText: l10n.adminReason, helperText: l10n.adminReasonHint),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(key: const Key('narrow-confirm'), onPressed: _confirm, child: Text(l10n.actionContinue)),
      ],
    );
  }
}
