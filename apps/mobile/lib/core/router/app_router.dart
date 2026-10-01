import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/authors/presentation/author_screen.dart';
import '../../features/books/presentation/book_detail_screen.dart';
import '../../features/books/presentation/explore_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/questions/presentation/study_screen.dart';

/// Routes that persist data or need identity. Everything else is open to guests (owner decision).
const signedInOnlyPrefixes = ['/library', '/profile'];

/// Pure redirect rule, unit-tested without widgets.
String? authRedirect({required AuthState? auth, required Uri location}) {
  final path = location.path;
  final onAuthScreen = path == '/sign-in' || path == '/sign-in/mfa';
  if (auth == null) return null; // still restoring the session: don't bounce the user around
  if (auth is AuthMfaPending) {
    if (path == '/sign-in/mfa') return null;
    // Carry the destination through the second-factor step so the user returns where they started.
    final from = location.queryParameters['from'];
    return Uri(path: '/sign-in/mfa', queryParameters: from == null ? null : {'from': from}).toString();
  }
  final signedIn = auth is AuthSignedIn;
  if (!signedIn && signedInOnlyPrefixes.any(path.startsWith)) {
    return Uri(path: '/sign-in', queryParameters: {'from': location.toString()}).toString();
  }
  if (signedIn && onAuthScreen) {
    final from = location.queryParameters['from'];
    return from != null && from.startsWith('/') && !from.startsWith('//') ? from : '/';
  }
  if (!signedIn && path == '/sign-in/mfa') return '/sign-in';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(auth: ref.read(authControllerProvider).value, location: state.uri),
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (_, state) => SignInScreen(from: state.uri.queryParameters['from']),
      ),
      GoRoute(path: '/sign-in/mfa', builder: (_, _) => const MfaScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, _) => const ExploreScreen(),
                routes: [
                  GoRoute(
                    path: 'books/:id',
                    builder: (_, state) => BookDetailScreen(idOrSlug: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'authors/:slug',
                    builder: (_, state) => AuthorScreen(slug: state.pathParameters['slug']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/study', builder: (_, _) => const StudyScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/library', builder: (_, _) => const LibraryScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
});

class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return AdaptiveNavigationScaffold(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      body: shell,
      destinations: [
        AppDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: l10n.navHome),
        AppDestination(icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: l10n.navExplore),
        AppDestination(icon: Icons.school_outlined, selectedIcon: Icons.school, label: l10n.navStudy),
        AppDestination(icon: Icons.local_library_outlined, selectedIcon: Icons.local_library, label: l10n.navLibrary),
        AppDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: l10n.navProfile),
      ],
    );
  }
}
