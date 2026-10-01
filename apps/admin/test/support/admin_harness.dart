import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_admin/core/providers.dart';
import 'package:oceanbook_admin/core/router.dart';
import 'package:oceanbook_admin/features/catalog/admin_catalog_api.dart';
import 'package:oceanbook_admin/features/users/users_page.dart';
import 'package:oceanbook_admin/main.dart';

import 'fake_admin_catalog.dart';

export 'fake_admin_catalog.dart';

const staffUser = AppUser(
  id: 's1',
  displayName: 'Ops Lead',
  locale: 'en',
  signInMethods: ['password'],
  mfaEnabled: true,
);

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
    return staffUser;
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

Future<FakeAuth> pumpAdmin(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  AppUser? restored,
  AdminCatalogRepository? catalog,
  String? location,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuth()..restored = restored;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAuthRepositoryProvider.overrideWithValue(auth),
        adminUsersRepositoryProvider.overrideWithValue(FakeUsers()),
        adminCatalogRepositoryProvider.overrideWithValue(catalog ?? FakeAdminCatalog()),
      ],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (location != null) {
    ProviderScope.containerOf(tester.element(find.byType(AdminApp))).read(adminRouterProvider).go(location);
    await tester.pumpAndSettle();
  }
  return auth;
}
