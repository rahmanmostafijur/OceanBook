import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';

import '../features/auth/admin_sign_in_page.dart';
import '../features/users/users_page.dart';
import '../shell/admin_shell.dart';
import 'navigation.dart';
import 'providers.dart';

/// Every admin route needs a staff session; a pending second factor pins the MFA page. The server still
/// enforces permissions and the MFA-session requirement on each API call.
String? adminRedirect({required AuthState? auth, required Uri location}) {
  final path = location.path;
  if (auth == null) return null;
  if (auth is AuthMfaPending) return path == '/sign-in/mfa' ? null : '/sign-in/mfa';
  if (auth is AuthSignedOut) return path == '/sign-in' ? null : '/sign-in';
  return path.startsWith('/sign-in') ? '/' : null;
}

Widget _pageFor(AdminNavItem item) => switch (item.path) {
  '/users' => const UsersPage(),
  '/' => const _Dashboard(),
  _ => PlannedPage(item: item),
};

final adminRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(adminAuthProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => adminRedirect(auth: ref.read(adminAuthProvider).value, location: state.uri),
    routes: [
      GoRoute(path: '/sign-in', builder: (_, _) => const AdminSignInPage()),
      GoRoute(path: '/sign-in/mfa', builder: (_, _) => const AdminMfaPage()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.uri.path, child: child),
        routes: [
          for (final item in allAdminItems) GoRoute(path: item.path, builder: (_, _) => _pageFor(item)),
        ],
      ),
    ],
  );
});

class _Dashboard extends StatelessWidget {
  const _Dashboard();

  @override
  Widget build(BuildContext context) {
    final l10n = ObLocalizations.of(context);
    return EmptyState(
      icon: Icons.space_dashboard_outlined,
      title: l10n.adminNavDashboard,
      message: l10n.adminStaffOnly,
    );
  }
}
