import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../core/navigation.dart';
import '../core/providers.dart';

/// Desktop-first admin frame: a persistent, sectioned NavigationDrawer on wide screens; a modal drawer
/// behind a menu button on narrower windows. Content keeps a comfortable maximum width.
const double _maxLabelWidth = 200;

class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  int get _selected {
    final items = allAdminItems;
    final exact = items.indexWhere((i) => i.path == location);
    if (exact >= 0) return exact;
    final prefix = items.indexWhere((i) => i.path != '/' && location.startsWith(i.path));
    return prefix < 0 ? 0 : prefix;
  }

  Widget _drawer(BuildContext context, ObLocalizations l10n, {required bool modal}) {
    final theme = Theme.of(context);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
        child: Text(l10n.adminTitle, style: theme.textTheme.titleMedium),
      ),
    ];
    for (final section in adminNavigation) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
          child: Text(
            section.label(l10n),
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
      for (final item in section.items) {
        children.add(
          NavigationDrawerDestination(
            icon: Icon(item.icon),
            // Long labels (especially in Bangla) ellipsize instead of overflowing the fixed-width drawer.
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxLabelWidth),
              child: Text(item.label(l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        );
      }
    }
    return NavigationDrawer(
      selectedIndex: _selected,
      onDestinationSelected: (i) {
        if (modal) Navigator.of(context).pop();
        context.go(allAdminItems[i].path);
      },
      children: children,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final wide = WindowSize.of(context) >= WindowSize.large;
    final auth = ref.watch(adminAuthProvider).value;
    final user = auth is AuthSignedIn ? auth.user : null;
    final appBar = AppBar(
      title: Text(allAdminItems[_selected].label(l10n)),
      actions: [
        if (user != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Center(child: Text(user.displayName, style: Theme.of(context).textTheme.labelLarge)),
          ),
        IconButton(
          tooltip: l10n.actionSignOut,
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(adminAuthProvider.notifier).signOut(),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
    final body = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1440), child: child),
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            _drawer(context, l10n, modal: false),
            Expanded(
              child: Scaffold(appBar: appBar, body: body),
            ),
          ],
        ),
      );
    }
    return Scaffold(appBar: appBar, drawer: _drawer(context, l10n, modal: true), body: body);
  }
}

/// Destinations scheduled for a later phase: say so honestly instead of showing a fake screen.
class PlannedPage extends StatelessWidget {
  const PlannedPage({required this.item, super.key});

  final AdminNavItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return EmptyState(
      icon: item.icon,
      title: item.label(l10n),
      message: l10n.adminComingInPhase(item.phase),
    );
  }
}
