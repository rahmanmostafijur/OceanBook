import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../auth/presentation/auth_controller.dart';
import '../../data/library_providers.dart';
import '../library_labels.dart';
import 'shelf_dialogs.dart';

/// Library controls on a catalog book page: add the book, or change its status, favourite it and
/// remove it. Guests get a sign-in prompt that returns them to [returnTo].
class LibraryActions extends ConsumerWidget {
  const LibraryActions({required this.bookId, required this.title, required this.returnTo, super.key});

  final String bookId;
  final String title;
  final String returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final signedIn = ref.watch(authControllerProvider).value is AuthSignedIn;
    if (!signedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            key: const Key('library-add'),
            onPressed: () => context.go(Uri(path: '/sign-in', queryParameters: {'from': returnTo}).toString()),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(l10n.libraryAddToLibrary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.librarySignInToAdd,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    final loaded = ref.watch(libraryProvider).hasValue;
    final item = ref.watch(libraryItemProvider(bookId));
    final controller = ref.read(libraryProvider.notifier);
    if (item == null) {
      return OutlinedButton.icon(
        key: const Key('library-add'),
        onPressed: loaded
            ? () => runReporting(context, () => controller.save(bookId), success: l10n.libraryAdded)
            : null,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: Text(l10n.libraryAddToLibrary),
      );
    }
    final (background, foreground) = shelfStatusColors(context, item.status);
    return Row(
      children: [
        Expanded(
          child: MenuAnchor(
            builder: (context, menu, _) => FilledButton.icon(
              key: const Key('library-status'),
              style: FilledButton.styleFrom(backgroundColor: background, foregroundColor: foreground),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              icon: Icon(shelfStatusIcon(item.status)),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(shelfStatusLabel(l10n, item.status), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
            menuChildren: [
              for (final status in ShelfStatus.values)
                MenuItemButton(
                  leadingIcon: Icon(shelfStatusIcon(status)),
                  trailingIcon: status == item.status ? const Icon(Icons.check) : null,
                  onPressed: status == item.status
                      ? null
                      : () => runReporting(context, () => controller.save(bookId, status: status)),
                  child: Text(shelfStatusLabel(l10n, status)),
                ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final confirmed = await confirmDestructive(
                    context,
                    title: l10n.libraryRemoveConfirmTitle,
                    message: l10n.libraryRemoveConfirmMessage(title),
                    confirmLabel: l10n.libraryRemoveAction,
                  );
                  if (confirmed && context.mounted) {
                    await runReporting(context, () => controller.remove(bookId), success: l10n.libraryRemoved);
                  }
                },
                child: Text(l10n.libraryRemove),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton.outlined(
          key: const Key('library-favorite'),
          tooltip: item.isFavorite ? l10n.libraryUnmarkFavorite : l10n.libraryMarkFavorite,
          isSelected: item.isFavorite,
          onPressed: () => runReporting(context, () => controller.save(bookId, isFavorite: !item.isFavorite)),
          icon: const Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite, color: Theme.of(context).colorScheme.error),
        ),
      ],
    );
  }
}
