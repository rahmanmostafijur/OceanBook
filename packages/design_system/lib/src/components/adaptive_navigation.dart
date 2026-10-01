import 'package:flutter/material.dart';

import '../tokens/app_breakpoints.dart';
import '../tokens/app_spacing.dart';

/// One navigation destination, shared by NavigationBar / NavigationRail / NavigationDrawer.
@immutable
class AppDestination {
  const AppDestination({required this.icon, required this.selectedIcon, required this.label, this.badgeCount});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badgeCount;
}

/// Material 3 adaptive navigation:
/// compact -> NavigationBar, medium/expanded -> NavigationRail, large+ -> persistent NavigationDrawer.
/// The body is never stretched edge to edge on wide screens: callers constrain their content.
class AdaptiveNavigationScaffold extends StatelessWidget {
  const AdaptiveNavigationScaffold({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.railLeading,
    this.drawerHeader,
    super.key,
  });

  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? railLeading;
  final Widget? drawerHeader;

  @override
  Widget build(BuildContext context) {
    final size = WindowSize.of(context);
    Widget icon(AppDestination d, {required bool selected}) {
      final child = Icon(selected ? d.selectedIcon : d.icon);
      final count = d.badgeCount;
      return count == null || count == 0 ? child : Badge.count(count: count, child: child);
    }

    if (size.isCompact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: icon(d, selected: false),
                selectedIcon: icon(d, selected: true),
                label: d.label,
              ),
          ],
        ),
      );
    }
    if (size >= WindowSize.large) {
      return Scaffold(
        body: Row(
          children: [
            NavigationDrawer(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              children: [
                ?drawerHeader,
                const SizedBox(height: AppSpacing.xs),
                for (final d in destinations)
                  NavigationDrawerDestination(
                    icon: icon(d, selected: false),
                    selectedIcon: icon(d, selected: true),
                    label: Text(d.label),
                  ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            leading: railLeading,
            groupAlignment: -0.85,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: icon(d, selected: false),
                  selectedIcon: icon(d, selected: true),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Centres content at a readable maximum width with the window-class gutter.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({required this.child, this.maxWidth = 1200, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter(width)),
          child: child,
        ),
      ),
    );
  }
}
