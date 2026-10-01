// Runs in its own isolate with the real Noto Sans Bengali font loaded. Kept apart from the pixel-based
// accessibility guideline tests, which sample anti-aliased glyph pixels and are calibrated for the
// standard test font (exact role-pair contrast is verified mathematically in design_system_test.dart).
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, String file) async {
  final bytes = File('fonts/$file').readAsBytesSync();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bangla text shaping', () {
    setUpAll(() async {
      await _loadFont('packages/design_system/${AppTypography.bengaliFamily}', 'NotoSansBengali-Variable.ttf');
    });

    double width(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontFamily: 'packages/design_system/${AppTypography.bengaliFamily}', fontSize: 40),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    test('conjuncts are shaped (ক্ষ is narrower than its letters drawn apart)', () {
      final conjunct = width('ক্ষ'); // ka + virama + ssa -> one ligature
      final apart = width('ক') + width('্') + width('ষ');
      expect(conjunct, greaterThan(0));
      expect(conjunct, lessThan(apart * 0.9));
    });

    test('vowel signs attach instead of rendering as separate glyph boxes', () {
      expect(width('কি'), lessThan(width('ক') + width('ি') * 1.5));
    });
  });
}
