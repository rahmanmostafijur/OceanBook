import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import '../../core/providers.dart';
import 'content_sources_page.dart';
import 'rights_api.dart';
import 'rights_labels.dart';

final rightsQueueProvider = FutureProvider.autoDispose<List<ProvenanceRecord>>(
  (ref) => ref.watch(rightsRepositoryProvider).queue(),
);

String _day(DateTime? d) => d == null ? '–' : d.toIso8601String().substring(0, 10);

/// Submitted provenance waiting for a second person. Verifying needs someone who neither recorded nor last
/// edited the entry; the buttons explain that, and the server enforces it.
class RightsQueuePage extends ConsumerStatefulWidget {
  const RightsQueuePage({super.key});

  @override
  ConsumerState<RightsQueuePage> createState() => _RightsQueuePageState();
}

class _RightsQueuePageState extends ConsumerState<RightsQueuePage> {
  String? _busyId;
  String? _error;

  Future<void> _decide(ProvenanceRecord record, {required bool verified}) async {
    final l10n = ObLocalizations.of(context);
    String? notes;
    if (!verified) {
      notes = await showDialog<String>(context: context, builder: (_) => const _NotesDialog());
      if (notes == null) return;
    }
    setState(() {
      _busyId = record.id;
      _error = null;
    });
    try {
      await ref.read(rightsRepositoryProvider).decide(record.id, verified: verified, notes: notes);
      ref.invalidate(rightsQueueProvider);
    } on Object catch (error) {
      setState(() => _error = adminFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final me = switch (ref.watch(adminAuthProvider).value) {
      AuthSignedIn(:final user) => user.id,
      _ => null,
    };
    final sources = {
      for (final s in ref.watch(contentSourcesProvider).value ?? const <ContentSource>[]) s.id: s.name.resolve(locale),
    };
    return switch (ref.watch(rightsQueueProvider)) {
      AsyncData(:final value) when value.isEmpty => EmptyState(
        icon: Icons.verified_outlined,
        title: l10n.adminQueueEmpty,
      ),
      AsyncData(:final value) => ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                _error!,
                key: const Key('queue-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          for (final record in value)
            Card(
              key: Key('queue-${record.id}'),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sources[record.sourceId] ?? record.sourceId, style: theme.textTheme.titleMedium),
                    Text(
                      '${licenseLabel(l10n, record.licenseType)} · ${rightsLabel(l10n, record.rightsStatus)}',
                    ),
                    Text(
                      '${record.territories.join(', ')} · ${_day(record.validFrom)} → ${_day(record.validUntil)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (record.sourceUrl != null) Text(record.sourceUrl!, style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppSpacing.sm),
                    if (me != null && record.touchedBy(me))
                      Text(l10n.errorSelfVerification, style: theme.textTheme.bodySmall),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        FilledButton(
                          key: Key('verify-${record.id}'),
                          onPressed: _busyId != null || (me != null && record.touchedBy(me))
                              ? null
                              : () => _decide(record, verified: true),
                          child: Text(l10n.adminActionVerify),
                        ),
                        OutlinedButton(
                          key: Key('reject-${record.id}'),
                          onPressed: _busyId != null || (me != null && record.touchedBy(me))
                              ? null
                              : () => _decide(record, verified: false),
                          child: Text(l10n.adminActionReject),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(rightsQueueProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// A rejection needs notes the author can act on (server rule: required, at most 2000 characters).
class _NotesDialog extends StatefulWidget {
  const _NotesDialog();

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminActionReject),
      content: TextField(
        key: const Key('reject-notes'),
        controller: _controller,
        autofocus: true,
        maxLength: 2000,
        maxLines: 3,
        decoration: InputDecoration(labelText: l10n.adminRejectNotes),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(key: const Key('reject-confirm'), onPressed: _confirm, child: Text(l10n.actionContinue)),
      ],
    );
  }
}
