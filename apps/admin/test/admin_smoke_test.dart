import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/core/navigation.dart';
import 'package:oceanbook_admin/core/providers.dart';
import 'package:oceanbook_admin/core/router.dart';
import 'package:oceanbook_admin/features/users/users_page.dart';
import 'package:oceanbook_admin/main.dart';

const _staff = AppUser(id: 's1', displayName: 'Ops Lead', locale: 'en', signInMethods: ['password'], mfaEnabled: true);

class FakeAuth implements AuthRepository {
  AppUser? restored;
  final List<String> calls = [];

  @override
  Future<AppUser?> restoreSession() async => restored;

  @override
  Future<SignInOutcome> signInWithPassword({required String email, required String password}) async {
    calls.add('password:$email');
    return const MfaRequired(mfaToken: 'challenge', methods: ['totp']);
  }

  @override
  Future<AppUser> completeMfa({required String mfaToken, String? code, String? recoveryCode}) async {
    calls.add('mfa:$code');
    return _staff;
  }

  @override
  Future<void> signOut() async => calls.add('signout');

  @override
  Future<SignInOutcome> register({required String email, required String password, required String displayName}) =>
      throw UnimplementedError();

  @override
  Future<OtpSent> startPhoneSignIn(String phone) => throw UnimplementedError();

  @override
  Future<SignInOutcome> verifyPhoneSignIn({required String phone, required String code, String? displayName}) =>
      throw UnimplementedError();
}

class FakeUsers implements AdminUsersRepository {
  @override
  Future<UserPage> search({String? query, int page = 1, int pageSize = 25}) async => const UserPage(
    rows: [
      AdminUserRow(id: '1', displayName: 'রফিক', email: 'rafiq@example.org', status: 'active', roles: ['student']),
      AdminUserRow(id: '2', displayName: 'Ops Lead', email: 'ops@example.org', status: 'active', roles: ['admin']),
    ],
    total: 2,
    page: 1,
    pageSize: 25,
  );
}

Future<FakeAuth> pumpAdmin(WidgetTester tester, {Size size = const Size(1440, 900), AppUser? restored}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuth()..restored = restored;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAuthRepositoryProvider.overrideWithValue(auth),
        adminUsersRepositoryProvider.overrideWithValue(FakeUsers()),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

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
    expect(adminRedirect(auth: const AuthSignedIn(_staff), location: Uri.parse('/sign-in')), '/');
    expect(adminRedirect(auth: const AuthSignedIn(_staff), location: Uri.parse('/books')), isNull);
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
    await pumpAdmin(tester, restored: _staff);
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
    await pumpAdmin(tester, size: const Size(1024, 768), restored: _staff);
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
    await pumpAdmin(tester, restored: _staff);
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('রফিক'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
  });

  testWidgets('admin shell meets Material accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAdmin(tester, restored: _staff);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
