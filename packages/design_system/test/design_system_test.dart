import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('colour contrast (WCAG 2.2 AA, 4.5:1 for text)', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name} scheme role pairs', () {
        final s = AppColors.scheme(brightness);
        final pairs = <String, (Color, Color)>{
          'primary': (s.onPrimary, s.primary),
          'primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
          'secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
          'tertiaryContainer': (s.onTertiaryContainer, s.tertiaryContainer),
          'error': (s.onError, s.error),
          'errorContainer': (s.onErrorContainer, s.errorContainer),
          'surface': (s.onSurface, s.surface),
          'surfaceVariant text': (s.onSurfaceVariant, s.surface),
          'surfaceContainerLow': (s.onSurface, s.surfaceContainerLow),
          'surfaceContainerHigh': (s.onSurface, s.surfaceContainerHigh),
          'inverseSurface': (s.onInverseSurface, s.inverseSurface),
        };
        for (final MapEntry(key: name, value: (fg, bg)) in pairs.entries) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$name in ${brightness.name}');
        }
      });

      test('${brightness.name} semantic roles and highlight colours', () {
        final x = AppSemanticColors.forBrightness(brightness);
        final s = AppColors.scheme(brightness);
        expect(contrast(x.onSuccess, x.success), greaterThanOrEqualTo(4.5));
        expect(contrast(x.onSuccessContainer, x.successContainer), greaterThanOrEqualTo(4.5));
        expect(contrast(x.onPremium, x.premium), greaterThanOrEqualTo(4.5));
        expect(contrast(x.onPremiumContainer, x.premiumContainer), greaterThanOrEqualTo(4.5));
        for (final colour in HighlightColor.values) {
          // Highlighted text keeps the normal text colour: it must stay readable on every highlight.
          expect(contrast(s.onSurface, x.highlights[colour]), greaterThanOrEqualTo(4.5), reason: colour.name);
        }
      });
    }
  });

  group('breakpoints map the required test sizes', () {
    final cases = <(double, double), WindowSize>{
      (360, 800): WindowSize.compact,
      (390, 844): WindowSize.compact,
      (412, 915): WindowSize.compact,
      (768, 1024): WindowSize.medium,
      (1024, 1366): WindowSize.expanded,
      (800, 360): WindowSize.medium, // phone landscape
      (1366, 1024): WindowSize.large, // tablet landscape / small desktop
      (1920, 1080): WindowSize.extraLarge,
    };
    for (final MapEntry(key: (w, h), value: expected) in cases.entries) {
      test('${w.toInt()}x${h.toInt()} -> ${expected.name}', () => expect(WindowSize.fromWidth(w), expected));
    }
  });

  group('theme', () {
    test('Material 3 with Noto fonts and Bengali fallback, both brightnesses', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.useMaterial3, isTrue);
        final body = theme.textTheme.bodyLarge!;
        expect(body.fontFamily, contains(AppTypography.uiFamily));
        expect(body.fontFamilyFallback, contains('packages/design_system/${AppTypography.bengaliFamily}'));
        expect(body.height, greaterThanOrEqualTo(1.5)); // room for Bangla matras and conjuncts
        expect(theme.extension<AppSemanticColors>(), isNotNull);
      }
      expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    test('touch targets: standard density keeps 48dp minimums; admin is compact', () {
      final mobile = AppTheme.light();
      expect(mobile.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(mobile.filledButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
      final admin = AppTheme.light(density: AppDensity.compact);
      expect(admin.visualDensity, VisualDensity.compact);
      expect(admin.colorScheme, mobile.colorScheme); // same tokens, different density only
    });
  });

  group('components', () {
    Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: child));
    }

    AdaptiveNavigationScaffold shell() => AdaptiveNavigationScaffold(
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      body: const Center(child: Text('body')),
      destinations: const [
        AppDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
        AppDestination(icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: 'Explore'),
        AppDestination(icon: Icons.school_outlined, selectedIcon: Icons.school, label: 'Study', badgeCount: 2),
      ],
    );

    testWidgets('NavigationBar on phones', (tester) async {
      await pumpAt(tester, const Size(390, 844), shell());
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('NavigationRail on tablets', (tester) async {
      await pumpAt(tester, const Size(768, 1024), shell());
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('persistent NavigationDrawer on large screens', (tester) async {
      await pumpAt(tester, const Size(1366, 1024), shell());
      expect(find.byType(NavigationDrawer), findsOneWidget);
    });

    testWidgets('meets Material accessibility guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAt(
        tester,
        const Size(390, 844),
        Scaffold(
          body: ListView(
            children: [
              const SectionHeader(title: 'Popular books'),
              const AccessChip(badge: AccessBadge.free, label: 'Free'),
              const AccessChip(badge: AccessBadge.premium, label: 'Premium'),
              const SizedBox(width: 120, child: BookCover(title: 'পদার্থবিজ্ঞান')),
              FilledButton(onPressed: () {}, child: const Text('Read preview')),
              IconButton(onPressed: () {}, tooltip: 'Bookmark', icon: const Icon(Icons.bookmark_border)),
              const EmptyState(icon: Icons.bookmarks_outlined, title: 'No bookmarks yet', message: 'Tap the icon.'),
            ],
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('book cover keeps 2:3 and is announced exactly once without an image', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAt(
        tester,
        const Size(390, 844),
        const Center(
          child: SizedBox(width: 120, child: BookCover(title: 'Algebra')),
        ),
      );
      expect(tester.getSize(find.byType(AspectRatio)), const Size(120, 180));
      expect(find.bySemanticsLabel('Algebra'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('skeleton does not animate under reduced motion', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Skeleton(width: 100),
          ),
        ),
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
