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
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(name == null ? _greeting(l10n, DateTime.now()) : '${_greeting(l10n, DateTime.now())}, $name'),
            actions: [
              IconButton(
                tooltip: l10n.notificationsTitle,
                onPressed: () {},
                icon: const Icon(Icons.notifications_none),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: ConstrainedContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Entry point to search (which lives in Explore): one full-size, labelled button for
                  // assistive tech; the decorative bar inside is excluded from semantics.
                  Semantics(
                    container: true,
                    button: true,
                    label: l10n.searchHint,
                    onTap: () => context.go('/explore'),
                    child: ExcludeSemantics(
                      child: SearchBar(
                        hintText: l10n.searchHint,
                        leading: const Icon(Icons.search),
                        onTap: () => context.go('/explore'),
                      ),
                    ),
                  ),
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
      AsyncData(:final value) => SizedBox(
        height: 330,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, index) => BookTile(book: value[index], width: _railTileWidth),
        ),
      ),
      AsyncError(:final error) => Text(failureMessage(l10n, error), style: hint),
      _ => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
    };
  }
}
