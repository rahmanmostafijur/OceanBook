import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('settings are grouped and sign-out asks first', (tester) async {
    final auth = await pumpApp(tester, restored: testUser, location: '/profile');
    for (final section in ['Account', 'Appearance', 'Premium', 'About']) {
      expect(find.text(section), findsWidgets);
    }
    expect(find.text('Nusrat'), findsOneWidget);
    expect(find.text("Premium plans aren't available to buy yet."), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 0);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
  });

  testWidgets('the theme choice applies at once', (tester) async {
    await pumpApp(tester, restored: testUser, location: '/profile');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Appearance'))).brightness, Brightness.dark);
  });

  for (final locale in [const Locale('en'), const Locale('bn')]) {
    testWidgets('settings have no overflow at 200 % text on a small phone (${locale.languageCode})', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, restored: testUser, location: '/profile', size: const Size(320, 640), locale: locale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings meet accessibility guidelines', (tester) async {
    await pumpApp(tester, restored: testUser, location: '/profile');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });
}
