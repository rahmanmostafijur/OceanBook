import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/core/navigation.dart';
import 'package:oceanbook_admin/core/router.dart';

import 'support/admin_harness.dart';

void main() {
  test('every admin route requires a staff session; MFA pending pins the MFA page', () {
    expect(adminRedirect(auth: const AuthSignedOut(), location: Uri.parse('/users')), '/sign-in');
    expect(
      adminRedirect(
        auth: const AuthMfaPending(mfaToken: 't', methods: ['totp']),
        location: Uri.parse('/'),
      ),
      '/sign-in/mfa',
    );
    expect(adminRedirect(auth: const AuthSignedIn(staffUser), location: Uri.parse('/sign-in')), '/');
    expect(adminRedirect(auth: const AuthSignedIn(staffUser), location: Uri.parse('/books')), isNull);
  });

  test('navigation covers every section the owner listed, each with a unique route', () {
    final paths = allAdminItems.map((i) => i.path).toList();
    expect(paths.toSet().length, paths.length);
    expect(
      paths,
      containsAll([
        '/users',
        '/roles',
        '/books',
        '/authors',
        '/publishers',
        '/categories',
        '/content-sources',
        '/rights',
        '/questions',
        '/subjects',
        '/chapters',
        '/topics',
        '/question-papers',
        '/quizzes',
        '/exams',
        '/subscriptions',
        '/entitlements',
        '/payments',
        '/analytics',
        '/notifications',
        '/audit-logs',
        '/system-health',
        '/',
      ]),
    );
  });

  testWidgets('staff sign-in goes through MFA to the dashboard', (tester) async {
    final auth = await pumpAdmin(tester);
    expect(find.text('Staff sign-in'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('email')), 'ops@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'correct-horse-battery');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Two-step verification'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('otp')), '123456');
    await tester.tap(find.byKey(const Key('verify')));
    await tester.pumpAndSettle();
    expect(auth.calls, ['password:ops@example.org', 'mfa:123456']);
    expect(find.text('Ops Lead'), findsOneWidget);
  });

  testWidgets('desktop: persistent drawer with all sections; planned pages say which phase', (tester) async {
    await pumpAdmin(tester, restored: staffUser);
    expect(find.byType(NavigationDrawer), findsOneWidget);
    final drawerScroll = find.descendant(of: find.byType(NavigationDrawer), matching: find.byType(Scrollable));
    for (final label in [
      'People',
      'Catalog',
      'Content & rights',
      'Question bank',
      'Assessment',
      'Commerce',
      'Operations',
    ]) {
      await tester.scrollUntilVisible(find.text(label), 120, scrollable: drawerScroll);
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Payments'));
    await tester.pumpAndSettle();
    expect(find.text('Available in phase 5'), findsOneWidget);
  });

  testWidgets('tablet width: drawer becomes modal behind the menu button', (tester) async {
    await pumpAdmin(tester, size: const Size(1024, 768), restored: staffUser);
    expect(find.byType(NavigationDrawer), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsOneWidget);
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDrawer), findsNothing);
    expect(find.text('rafiq@example.org'), findsOneWidget);
  });

  testWidgets('users table renders Bangla names and roles', (tester) async {
    await pumpAdmin(tester, restored: staffUser);
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('রফিক'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
  });

  testWidgets('admin shell meets Material accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAdmin(tester, restored: staffUser);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
