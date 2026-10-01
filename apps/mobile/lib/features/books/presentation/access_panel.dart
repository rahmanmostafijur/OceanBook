import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

/// Read / preview actions from the server's access block. Buttons are enabled only when the server
/// says the caller may read *and* that the reader is available (Phase 4); the client decides nothing.
class AccessPanel extends StatelessWidget {
  const AccessPanel({required this.access, required this.returnTo, super.key});

  final BookAccess access;

  /// Where sign-in should return to.
  final String returnTo;

  String? _explanation(ObLocalizations l10n) {
    if (access.needsSignIn) return l10n.bookSignInToRead;
    if (access.needsEntitlement) return l10n.bookPremiumRequired;
    if (access.reasons.contains(AccessReason.rightsRestricted)) return l10n.bookRightsRestricted;
    if (access.state == AccessState.unavailable) return l10n.bookNotAvailable;
    if (!access.readerAvailable) return l10n.readingComingSoon;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final explanation = _explanation(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('read-now'),
          onPressed: access.readEnabled ? () {} : null,
          icon: const Icon(Icons.chrome_reader_mode_outlined),
          label: Text(l10n.actionReadNow),
        ),
        if (access.canPreview) ...[
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            key: const Key('read-preview'),
            onPressed: access.previewEnabled ? () {} : null,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(l10n.actionReadPreview),
          ),
        ],
        if (explanation != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            explanation,
            key: const Key('access-explanation'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (access.needsSignIn)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('access-sign-in'),
              onPressed: () => context.go(Uri(path: '/sign-in', queryParameters: {'from': returnTo}).toString()),
              child: Text(l10n.actionSignIn),
            ),
          ),
      ],
    );
  }
}
