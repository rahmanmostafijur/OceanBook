import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../core/messages.dart';
import 'admin_catalog_api.dart';
import 'books_page.dart';

final adminBookProvider = FutureProvider.autoDispose.family<AdminBook, String>(
  (ref, id) => ref.watch(adminCatalogRepositoryProvider).book(id),
);

/// One book for staff: translations, contributors, editions with their publish-gate status, and the
/// workflow actions its status allows. The server decides whether each action is permitted.
class BookDetailPage extends ConsumerWidget {
  const BookDetailPage({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    return switch (ref.watch(adminBookProvider(bookId))) {
      AsyncValue(:final value?) => _BookView(book: value),
      AsyncError(:final error) => ErrorState(
        title: l10n.errorTitle,
        message: adminFailureMessage(l10n, error),
        retryLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(adminBookProvider(bookId)),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _BookView extends ConsumerStatefulWidget {
  const _BookView({required this.book});

  final AdminBook book;

  @override
  ConsumerState<_BookView> createState() => _BookViewState();
}

class _BookViewState extends ConsumerState<_BookView> {
  bool _busy = false;
  String? _error;
  List<String> _blockReasons = const [];

  Future<void> _run(BookAction action) async {
    final l10n = ObLocalizations.of(context);
    String? reason;
    if (action.needsReason) {
      reason = await _askReason(context, l10n);
      if (reason == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _blockReasons = const [];
    });
    try {
      await ref.read(adminCatalogRepositoryProvider).transition(widget.book.id, action, reason: reason);
      ref
        ..invalidate(adminBookProvider(widget.book.id))
        ..invalidate(adminBooksProvider);
    } on Object catch (error) {
      setState(() {
        _error = adminFailureMessage(l10n, error);
        _blockReasons = blockReasonsOf(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _actionLabel(ObLocalizations l10n, BookAction action) => switch (action) {
    BookAction.submit => l10n.adminActionSubmit,
    BookAction.requestChanges => l10n.adminActionRequestChanges,
    BookAction.publish => l10n.adminActionPublish,
    BookAction.unpublish => l10n.adminActionUnpublish,
    BookAction.archive => l10n.adminActionArchive,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final book = widget.book;
    final actions = actionsFor(book.status);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text(book.title, style: theme.textTheme.headlineSmall)),
            ),
            StatusChip(status: book.status),
          ],
        ),
        Text('${book.slug} · ${accessLabel(l10n, book.accessLevel)}', style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (index, action) in actions.indexed)
              index == 0
                  ? FilledButton(
                      key: Key('action-${action.path}'),
                      onPressed: _busy ? null : () => _run(action),
                      child: Text(_actionLabel(l10n, action)),
                    )
                  : OutlinedButton(
                      key: Key('action-${action.path}'),
                      onPressed: _busy ? null : () => _run(action),
                      child: Text(_actionLabel(l10n, action)),
                    ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            key: const Key('action-error'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
          for (final reason in _blockReasons) Text('• ${gateReason(l10n, reason)}'),
        ],
        SectionHeader(title: l10n.adminTranslations),
        for (final t in book.translations)
          ListTile(
            leading: Text(t.locale.toUpperCase(), style: theme.textTheme.labelLarge),
            title: Text(t.title),
            trailing: StatusChip(status: t.status == 'published' ? 'published' : 'draft'),
          ),
        if (book.contributors.isNotEmpty) ...[
          SectionHeader(title: l10n.adminContributors),
          Text(book.contributors.join(', ')),
        ],
        SectionHeader(title: l10n.adminEditions),
        for (final edition in book.editions)
          _EditionCard(edition: edition, isDefault: edition.id == book.defaultEditionId),
      ],
    );
  }
}

Future<String?> _askReason(BuildContext context, ObLocalizations l10n) =>
    showDialog<String>(context: context, builder: (_) => const _ReasonDialog());

/// Owns its controller, so the text field outlives the closing animation safely.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (text.length >= 3) Navigator.of(context).pop(text); // the server requires 3..500 characters
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.adminReason),
      content: TextField(
        key: const Key('reason-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(helperText: l10n.adminReasonHint),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.actionCancel)),
        FilledButton(key: const Key('reason-confirm'), onPressed: _confirm, child: Text(l10n.actionContinue)),
      ],
    );
  }
}

class _EditionCard extends StatelessWidget {
  const _EditionCard({required this.edition, required this.isDefault});

  final AdminEdition edition;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(edition.label, style: theme.textTheme.titleMedium)),
                if (isDefault) const Icon(Icons.star_outline, size: AppSizes.iconSmall),
                const SizedBox(width: AppSpacing.xs),
                StatusChip(status: edition.status),
              ],
            ),
            Text(
              [edition.language, ?edition.isbn13, l10n.adminChapters(edition.chapterCount)].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              key: Key('gate-${edition.id}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  edition.publishable ? Icons.verified_outlined : Icons.block,
                  size: AppSizes.iconSmall,
                  color: edition.publishable ? semantic.success : theme.colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(edition.publishable ? l10n.adminGateReady : l10n.adminGateBlocked),
                      for (final reason in edition.blockReasons)
                        Text(gateReason(l10n, reason), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
