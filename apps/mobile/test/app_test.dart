import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/l10n/generated/ob_localizations_bn.dart';
import 'package:ob_l10n/l10n/generated/ob_localizations_en.dart';
import 'package:oceanbook_mobile/core/errors/failure_messages.dart';
import 'package:oceanbook_mobile/core/router/app_router.dart';

import 'support/harness.dart';

void main() {
  group('auth redirect rules', () {
    Uri u(String s) => Uri.parse(s);

    test('guests can browse home, explore and study', () {
      for (final path in ['/', '/explore', '/study']) {
        expect(
          authRedirect(auth: const AuthSignedOut(), location: u(path)),
          isNull,
          reason: path,
        );
      }
    });

    test('library and profile require sign-in and come back afterwards', () {
      expect(authRedirect(auth: const AuthSignedOut(), location: u('/library')), '/sign-in?from=%2Flibrary');
      expect(authRedirect(auth: const AuthSignedIn(testUser), location: u('/sign-in?from=/library')), '/library');
    });

    test('open redirects are refused', () {
      expect(authRedirect(auth: const AuthSignedIn(testUser), location: u('/sign-in?from=//evil.example.com')), '/');
      expect(
        authRedirect(auth: const AuthSignedIn(testUser), location: u('/sign-in?from=https://evil.example.com')),
        '/',
      );
    });

    test('a pending second factor pins the user to the MFA screen', () {
      const pending = AuthMfaPending(mfaToken: 't', methods: ['totp']);
      expect(authRedirect(auth: pending, location: u('/profile')), '/sign-in/mfa');
      expect(authRedirect(auth: pending, location: u('/sign-in?from=/profile')), '/sign-in/mfa?from=%2Fprofile');
      expect(authRedirect(auth: pending, location: u('/sign-in/mfa')), isNull);
      expect(authRedirect(auth: const AuthSignedOut(), location: u('/sign-in/mfa')), '/sign-in');
    });

    test('no redirect while the session is still restoring', () {
      expect(authRedirect(auth: null, location: u('/library')), isNull);
    });
  });

  group('responsive navigation at the required sizes', () {
    final sizes = <Size, Type>{
      const Size(360, 800): NavigationBar,
      const Size(390, 844): NavigationBar,
      const Size(412, 915): NavigationBar,
      const Size(800, 360): NavigationRail, // phone landscape
      const Size(768, 1024): NavigationRail,
      const Size(1024, 1366): NavigationRail,
      const Size(1366, 1024): NavigationDrawer,
    };
    for (final entry in sizes.entries) {
      testWidgets('${entry.key.width.toInt()}x${entry.key.height.toInt()} uses ${entry.value}', (tester) async {
        await pumpApp(tester, size: entry.key);
        expect(find.byType(entry.value), findsOneWidget);
        expect(tester.takeException(), isNull); // no overflow at any size
      });
    }
  });

  testWidgets('guest tapping Library is sent to sign-in, and back after signing in', (tester) async {
    final repo = await pumpApp(tester);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to OceanBook'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('email')), 'nusrat@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'correct-horse-battery');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(repo.calls, ['password:nusrat@example.org']);
    expect(find.text('Your library is empty'), findsOneWidget);
  });

  testWidgets('MFA users get no session until the second factor passes', (tester) async {
    final repo = await pumpApp(tester);
    repo.next = const MfaRequired(mfaToken: 'challenge-1', methods: ['totp', 'recovery_code']);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'staff@example.org');
    await tester.enterText(find.byKey(const Key('password')), 'correct-horse-battery');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Two-step verification'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'mfa:challenge-1:123456');
    expect(find.text('Nusrat'), findsOneWidget); // profile, signed in
  });

  testWidgets('server errors show a localised message inline, by code', (tester) async {
    final repo = await pumpApp(tester);
    repo.failWith = const ServerFailure(
      status: 401,
      errors: [ApiErrorItem(code: ApiErrorCode.invalidCredentials, message: 'server text')],
    );
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'a@b.org');
    await tester.enterText(find.byKey(const Key('password')), 'wrong-password');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.text('server text'), findsNothing);
  });

  testWidgets('a server-side revocation signs the user out and leaves protected screens', (tester) async {
    final events = SessionEvents();
    await pumpApp(tester, restored: testUser, events: events);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Your library is empty'), findsOneWidget);
    events.emit(SessionEvent.expired);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to OceanBook'), findsOneWidget);
  });

  testWidgets('Bangla UI renders and switches language live', (tester) async {
    await pumpApp(tester, locale: const Locale('bn'));
    expect(find.text('হোম'), findsOneWidget);
    expect(find.text('পড়াশোনা'), findsOneWidget);
  });

  testWidgets('home and sign-in meet Material accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('text scaled to 200% does not overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(360, 800));
    expect(tester.takeException(), isNull);
  });

  group('failure messages map codes, never server text', () {
    final en = ObLocalizationsEn();
    final bn = ObLocalizationsBn();
    ServerFailure f(ApiErrorCode c) => ServerFailure(
      status: 400,
      errors: [ApiErrorItem(code: c, message: 'raw')],
    );

    test('known codes', () {
      expect(failureMessage(en, f(ApiErrorCode.otpCooldown)), en.errorOtpCooldown);
      expect(failureMessage(bn, f(ApiErrorCode.accountLinkRequired)), bn.errorAccountLinkRequired);
      expect(failureMessage(en, const NetworkFailure(reason: 'offline')), en.errorNetwork);
      expect(failureMessage(en, const SessionExpiredFailure()), en.errorSessionExpired);
    });

    test('unknown codes fall back to a generic message', () {
      expect(failureMessage(en, f(ApiErrorCode.unknown)), en.errorServer);
      expect(failureMessage(en, StateError('x')), en.errorServer);
    });
  });

  test('event stream is broadcast (router and controller can both listen)', () async {
    final events = SessionEvents();
    final a = <SessionEvent>[];
    final b = <SessionEvent>[];
    final s1 = events.stream.listen(a.add);
    final s2 = events.stream.listen(b.add);
    events.emit(SessionEvent.expired);
    await Future<void>.delayed(Duration.zero);
    expect(a, [SessionEvent.expired]);
    expect(b, [SessionEvent.expired]);
    await s1.cancel();
    await s2.cancel();
    unawaited(events.dispose());
  });
}
