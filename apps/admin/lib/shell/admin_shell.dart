import 'dart:math' as math;

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
const double _minTileHeight = 56;
const double _tileVerticalPadding = 16;
const double _indicatorWidth = 336;

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

  /// The drawer tile height is fixed by Material, so it is computed from the longest label wrapped at
  /// [_maxLabelWidth] under the user's text scale: labels wrap instead of truncating.
  double _tileHeight(BuildContext context, ObLocalizations l10n) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var tallest = 0.0;
    for (final item in allAdminItems) {
      final painter = TextPainter(
        text: TextSpan(text: item.label(l10n), style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: _maxLabelWidth);
      tallest = math.max(tallest, painter.height);
      painter.dispose();
    }
    return math.max(_minTileHeight, tallest + _tileVerticalPadding);
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
            // Long labels (especially in Bangla) wrap within the label width; the tile grows to fit.
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxLabelWidth),
              child: Tooltip(
                message: item.label(l10n),
                child: Text(item.label(l10n)),
              ),
            ),
          ),
        );
      }
    }
    final tileHeight = _tileHeight(context, l10n);
    return Theme(
      data: theme.copyWith(
        navigationDrawerTheme: theme.navigationDrawerTheme.copyWith(
          tileHeight: tileHeight,
          indicatorSize: Size(_indicatorWidth, tileHeight),
        ),
      ),
      child: NavigationDrawer(
        selectedIndex: _selected,
        onDestinationSelected: (i) {
          if (modal) Navigator.of(context).pop();
          context.go(allAdminItems[i].path);
        },
        children: children,
      ),
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
