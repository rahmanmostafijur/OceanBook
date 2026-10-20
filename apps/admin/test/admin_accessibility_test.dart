import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/admin_harness.dart';

void main() {
  for (final scale in [2.0, 3.0]) {
    testWidgets('admin drawer labels wrap without truncation or overflow at ${scale * 100} % text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAdmin(tester, restored: staffUser, location: '/books');
      expect(tester.takeException(), isNull);

      final drawer = find.byType(NavigationDrawer);
      expect(drawer, findsOneWidget);
      final labels = find.descendant(of: drawer, matching: find.byType(RichText));
      expect(labels, findsWidgets);
      for (final element in labels.evaluate()) {
        final render = element.renderObject;
        if (render is RenderParagraph) {
          expect(render.didExceedMaxLines, isFalse, reason: render.text.toPlainText());
        }
      }
    });
  }

  testWidgets('skip link is reachable by keyboard and moves focus to the main content', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/books');

    final skip = find.widgetWithText(FilledButton, 'Skip to main content');
    expect(skip, findsOneWidget);
    // A fresh page load: nothing focused yet, so the first Tab goes to the first control in reading order.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    final reached =
        focused != null && find.descendant(of: skip, matching: find.byWidget(focused.widget)).evaluate().isNotEmpty;
    expect(reached, isTrue);
    final opacities = find
        .ancestor(of: skip, matching: find.byType(Opacity))
        .evaluate()
        .map((e) => (e.widget as Opacity).opacity);
    expect(opacities, everyElement(1.0));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'admin main content');
  });

  testWidgets('focus moves to the main content after navigating', (tester) async {
    await pumpAdmin(tester, restored: staffUser, location: '/books');
    final context = tester.element(
      find.byType(NavigationDrawer).evaluate().isNotEmpty ? find.byType(NavigationDrawer) : find.byType(Scaffold).first,
    );
    GoRouter.of(context).go('/users');
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'admin main content');
  });
}
