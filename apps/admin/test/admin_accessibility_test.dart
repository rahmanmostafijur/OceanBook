import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
