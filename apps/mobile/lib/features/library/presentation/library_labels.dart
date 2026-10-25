import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';

String shelfStatusLabel(ObLocalizations l10n, ShelfStatus status) => switch (status) {
  ShelfStatus.wantToRead => l10n.libraryStatusWantToRead,
  ShelfStatus.reading => l10n.libraryStatusReading,
  ShelfStatus.finished => l10n.libraryStatusFinished,
};

IconData shelfStatusIcon(ShelfStatus status) => switch (status) {
  ShelfStatus.wantToRead => Icons.bookmark_add_outlined,
  ShelfStatus.reading => Icons.auto_stories_outlined,
  ShelfStatus.finished => Icons.check_circle_outline,
};

/// Container / on-container pair for a status. The status is always written next to it as well.
(Color, Color) shelfStatusColors(BuildContext context, ShelfStatus status) {
  final scheme = Theme.of(context).colorScheme;
  final semantic = AppSemanticColors.of(context);
  return switch (status) {
    ShelfStatus.wantToRead => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    ShelfStatus.reading => (scheme.primaryContainer, scheme.onPrimaryContainer),
    ShelfStatus.finished => (semantic.successContainer, semantic.onSuccessContainer),
  };
}

String authorsOrUnknown(ObLocalizations l10n, LibraryItem book) {
  final names = book.authorNames;
  return names.isEmpty ? l10n.libraryUnknownAuthor : names.join(', ');
}

/// Language codes the catalog uses, named in the UI language; anything else falls back to the code.
String languageName(ObLocalizations l10n, String code) => switch (code) {
  'bn' => l10n.languageBangla,
  'en' => l10n.languageEnglish,
  _ => code.toUpperCase(),
};

String shortDate(BuildContext context, DateTime date) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(date.toLocal());

/// Runs [action] and reports a failure in a snack bar. Returns false when it failed.
Future<bool> runReporting(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = ObLocalizations.of(context);
  try {
    await action();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(failureMessage(l10n, error))));
    return false;
  }
}

/// Small rounded label with icon and text for a book's status.
class ShelfStatusBadge extends StatelessWidget {
  const ShelfStatusBadge({required this.status, super.key});

  final ShelfStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final (background, foreground) = shelfStatusColors(context, status);
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppShapes.small)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(shelfStatusIcon(status), size: 14, color: foreground),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                shelfStatusLabel(l10n, status),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
