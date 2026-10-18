import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../../core/errors/failure_messages.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../books/data/catalog_providers.dart';
import '../../books/presentation/widgets/book_tile.dart';

/// Home: a calm, mobile-first overview (not an admin dashboard). Sections fill in as their domains land:
/// catalog rails in M10, study progress in Phase 3, continue-reading in Phase 4.
/// How far the search bar hangs below the hero.
const double _searchOverlap = 28;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting(ObLocalizations l10n, DateTime now) {
    if (now.hour < 12) return l10n.homeGreetingMorning;
    if (now.hour < 17) return l10n.homeGreetingAfternoon;
    return l10n.homeGreetingEvening;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final auth = ref.watch(authControllerProvider).value;
    final name = auth is AuthSignedIn ? auth.user.displayName : null;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = AppSpacing.gutter(width);
    final greeting = name == null ? _greeting(l10n, DateTime.now()) : '${_greeting(l10n, DateTime.now())}, $name';
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The search bar overlaps the hero's lower edge. It sits inside the Stack's own bounds
                // (the hero is padded up by the overlap) because hit testing ignores anything outside them.
                Padding(
                  padding: const EdgeInsets.only(bottom: _searchOverlap),
                  child: OceanHero(
                    bottomInset: 56,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
                          child: _HeroContent(greeting: greeting),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: gutter,
                  right: gutter,
                  bottom: 0,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppSizes.maxReadableWidth - 2 * AppSpacing.xl),
                      // Entry point to search (which lives in Explore): one full-size, labelled button for
                      // assistive tech; the decorative bar inside is excluded from semantics.
                      child: Semantics(
                        container: true,
                        button: true,
                        label: l10n.searchHint,
                        onTap: () => context.go('/explore'),
                        child: ExcludeSemantics(
                          child: SearchBar(
                            hintText: l10n.searchHint,
                            leading: const Icon(Icons.search),
                            elevation: const WidgetStatePropertyAll(AppElevation.level3),
                            onTap: () => context.go('/explore'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
          SliverToBoxAdapter(
            child: ConstrainedContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _QuickActions(),
                  SectionHeader(title: l10n.homeStudyProgress),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: Text(l10n.homeSscPrep),
                      subtitle: Text(l10n.studyQuestionBank),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/study'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium_outlined),
                      title: Text(l10n.homeHscPrep),
                      subtitle: Text(l10n.studyPreviousPapers),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/study'),
                    ),
                  ),
                  SectionHeader(
                    title: l10n.homePopularBooks,
                    actionLabel: l10n.actionSeeAll,
                    onAction: () => context.go('/explore'),
                  ),
                  const _PopularRail(),
                  const SizedBox(height: AppSpacing.sectionGap),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text and the one accent button, on the hero's teal. Colours are all [ColorScheme] roles.
class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.greeting});

  final String greeting;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final onHero = theme.colorScheme.onPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                greeting,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(color: onHero),
              ),
            ),
            IconButton(
              tooltip: l10n.notificationsTitle,
              color: onHero,
              onPressed: () {},
              icon: const Icon(Icons.notifications_none),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            l10n.homeHeroTitle,
            style: theme.textTheme.displaySmall?.copyWith(color: onHero, fontWeight: FontWeight.w700, height: 1.2),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(l10n.homeHeroSubtitle, style: theme.textTheme.bodyLarge?.copyWith(color: onHero)),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: () => context.go('/explore'),
          icon: const Icon(Icons.explore_outlined),
          label: Text(l10n.homeHeroCta),
        ),
      ],
    );
  }
}

/// Three tonal tiles (the 30 % secondary colour) for the main places to go.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _QuickTile(icon: Icons.menu_book_outlined, label: l10n.homeQuickBooks, route: '/explore'),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _QuickTile(icon: Icons.history_edu_outlined, label: l10n.homeQuickPapers, route: '/study'),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _QuickTile(icon: Icons.bolt_outlined, label: l10n.homeQuickPractice, route: '/study'),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.route});

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: scheme.secondaryContainer,
        shape: AppShapes.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: scheme.onSecondaryContainer, size: AppSizes.icon + 4),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _railTileWidth = 140.0;
const _popular = BookQuery(sort: BookSort.popular);

/// Horizontal rail of popular published books. Failures stay inline: Home must never break.
class _PopularRail extends ConsumerWidget {
  const _PopularRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ObLocalizations.of(context);
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return switch (ref.watch(bookRailProvider(_popular))) {
      AsyncData(:final value) when value.isEmpty => Text(l10n.emptyBooks, style: hint),
      // Sized by its content (not a fixed height), so the rail grows with the user's text scale.
      AsyncData(:final value) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, book) in value.indexed) ...[
              if (index > 0) const SizedBox(width: AppSpacing.sm),
              BookTile(book: book, width: _railTileWidth),
            ],
          ],
        ),
      ),
      AsyncError(:final error) => Text(failureMessage(l10n, error), style: hint),
      _ => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
    };
  }
}
