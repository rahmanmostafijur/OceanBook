import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MarkerBuilder extends PageTransitionsBuilder {
  const _MarkerBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => KeyedSubtree(key: const Key('delegated'), child: child);
}

Future<void> _pumpTransition(WidgetTester tester, {required bool reduced}) async {
  const child = SizedBox(key: Key('page'));
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Builder(
        builder: (context) {
          final route = MaterialPageRoute<void>(builder: (_) => child);
          return const ReducedMotionPageTransitionsBuilder(
            _MarkerBuilder(),
          ).buildTransitions<void>(route, context, kAlwaysCompleteAnimation, kAlwaysDismissedAnimation, child);
        },
      ),
    ),
  );
}

void main() {
  group('PageLoading', () {
    testWidgets('exposes its label as a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PageLoading(semanticLabel: 'Loading books')),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Loading books'));
      expect(node.label, 'Loading books');
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      handle.dispose();
    });

    testWidgets('linear variant is also labelled and live', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PageLoading.linear(semanticLabel: 'Refreshing')),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Refreshing'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      handle.dispose();
    });
  });

  group('Skeleton.semanticLabel', () {
    testWidgets('is announced when provided', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: Skeleton(width: 40, semanticLabel: 'Loading title')),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Loading title'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('is hidden from assistive tech when null', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(body: Skeleton(width: 40)),
          ),
        ),
      );
      expect(find.descendant(of: find.byType(Skeleton), matching: find.byType(ExcludeSemantics)), findsWidgets);
      expect(tester.getSemantics(find.byType(Skeleton)).label, isEmpty);
      handle.dispose();
    });
  });

  group('ContentDocView.blankLabel', () {
    const doc = {
      'blocks': [
        {
          'type': 'paragraph',
          'inlines': [
            {'type': 'text', 'text': 'The capital is '},
            {'type': 'blank'},
          ],
        },
      ],
    };

    testWidgets('labels a blank for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ContentDocView(doc: doc, blankLabel: 'Blank')),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Blank')), findsOneWidget);
      handle.dispose();
    });
  });

  group('ReducedMotionPageTransitionsBuilder', () {
    testWidgets('returns the child unchanged when animations are disabled', (tester) async {
      await _pumpTransition(tester, reduced: true);
      expect(find.byKey(const Key('page')), findsOneWidget);
      expect(find.byKey(const Key('delegated')), findsNothing);
    });

    testWidgets('delegates when animations are enabled', (tester) async {
      await _pumpTransition(tester, reduced: false);
      expect(find.byKey(const Key('delegated')), findsOneWidget);
    });

    test('every platform in the app theme uses the reduced-motion wrapper', () {
      final builders = AppTheme.light().pageTransitionsTheme.builders;
      expect(builders.keys, hasLength(5));
      for (final builder in builders.values) {
        expect(builder, isA<ReducedMotionPageTransitionsBuilder>());
      }
    });
  });
}
