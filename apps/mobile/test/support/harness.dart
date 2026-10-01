import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_mobile/app.dart';
import 'package:oceanbook_mobile/core/network/api_providers.dart';
import 'package:oceanbook_mobile/core/router/app_router.dart';
import 'package:oceanbook_mobile/core/settings/app_settings.dart';
import 'package:oceanbook_mobile/features/auth/presentation/auth_controller.dart';
import 'package:oceanbook_mobile/features/books/data/catalog_providers.dart';

import 'fake_catalog.dart';

export 'fake_catalog.dart';

const testUser = AppUser(
  id: 'u1',
  displayName: 'Nusrat',
  locale: 'bn',
  email: 'nusrat@example.org',
  signInMethods: ['password'],
  mfaEnabled: false,
);

class FakeAuthRepository implements AuthRepository {
  AppUser? restored;
  SignInOutcome next = const SignedIn(testUser);
  ApiFailure? failWith;
  int signOuts = 0;
  final List<String> calls = [];

  @override
  Future<AppUser?> restoreSession() async => restored;

  @override
  Future<SignInOutcome> signInWithPassword({required String email, required String password}) async {
    calls.add('password:$email');
    if (failWith != null) throw failWith!;
    return next;
  }

  @override
  Future<SignInOutcome> register({
    required String email,
    required String password,
    required String displayName,
  }) async => next;

  @override
  Future<OtpSent> startPhoneSignIn(String phone) async {
    calls.add('phone:$phone');
    return const OtpSent(resendAfter: Duration(seconds: 60), expiresIn: Duration(minutes: 10));
  }

  @override
  Future<SignInOutcome> verifyPhoneSignIn({required String phone, required String code, String? displayName}) async =>
      next;

  @override
  Future<AppUser> completeMfa({required String mfaToken, String? code, String? recoveryCode}) async {
    calls.add('mfa:$mfaToken:${code ?? recoveryCode}');
    return testUser;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

Future<FakeAuthRepository> pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  AppUser? restored,
  SessionEvents? events,
  FakeCatalog? catalog,
  String? location,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeAuthRepository()..restored = restored;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        installationIdProvider.overrideWithValue('install-test'),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        if (events != null) sessionEventsProvider.overrideWithValue(events),
        localeProvider.overrideWith(() => _FixedLocale(locale)),
        catalogRepositoryProvider.overrideWithValue(catalog ?? FakeCatalog()),
      ],
      child: const OceanBookApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (location != null) {
    ProviderScope.containerOf(tester.element(find.byType(OceanBookApp))).read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }
  return repo;
}

class _FixedLocale extends LocaleNotifier {
  _FixedLocale(this.initial);
  final Locale initial;

  @override
  Locale build() => initial;
}
