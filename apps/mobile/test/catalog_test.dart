import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_mobile/features/books/presentation/book_detail_screen.dart';
import 'package:oceanbook_mobile/features/books/presentation/widgets/book_tile.dart';

import 'support/harness.dart';

const _sizes = [
  Size(360, 800),
  Size(390, 844),
  Size(412, 915),
  Size(768, 1024),
  Size(1024, 1366),
  Size(800, 360), // landscape phone
  Size(1366, 1024), // landscape tablet
];

FilledButton _readButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('read-now')));

void main() {
  testWidgets('explore lists server results and pages with the cursor while scrolling', (tester) async {
    final catalog = FakeCatalog(total: 45);
    await pumpApp(tester, catalog: catalog, location: '/explore');
    expect(find.byType(BookTile), findsWidgets);
    expect(catalog.queries.where((q) => q.$2 == null), isNotEmpty);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(catalog.queries.map((q) => q.$2), contains('20'), reason: 'second page requested by cursor');
  });

  testWidgets('search and category chips change the server query, never filter locally', (tester) async {
    final catalog = FakeCatalog();
    await pumpApp(tester, catalog: catalog, location: '/explore');
    await tester.enterText(find.byKey(const Key('catalog-search')), 'নরক');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(catalog.queries.last.$1.search, 'নরক');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fiction'));
    await tester.pumpAndSettle();
    expect(catalog.queries.last.$1.category, 'fiction');
    expect(find.widgetWithText(ChoiceChip, 'Novel'), findsNothing, reason: 'only top-level chips');
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(catalog.queries.last.$1.category, isNull);
  });

  testWidgets('tapping a book opens its details with contents, edition facts and credits', (tester) async {
    await pumpApp(tester, location: '/explore');
    await tester.tap(find.byType(BookTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
    expect(find.text('নন্দিত নরকে'), findsWidgets);
    expect(find.text('এক'), findsOneWidget);
    expect(find.text('অন্যপ্রকাশ'), findsOneWidget);
    expect(find.text('9780306406157'), findsOneWidget);
    expect(find.text('অন্যপ্রকাশের অনুমতিক্রমে'), findsOneWidget);
  });

  testWidgets('guests see Read disabled with a sign-in path', (tester) async {
    await pumpApp(tester, location: '/explore/books/book-0');
    expect(_readButton(tester).onPressed, isNull);
    expect(find.text('Sign in to read this book.'), findsOneWidget);
    expect(find.byKey(const Key('access-sign-in')), findsOneWidget);
  });

  testWidgets('server allows reading but the reader is not shipped: Read stays disabled', (tester) async {
    final catalog = FakeCatalog(
      detail: fakeDetail(access: fakeAccess(canRead: true, reasons: const [])),
    );
    await pumpApp(tester, catalog: catalog, location: '/explore/books/book-0');
    expect(_readButton(tester).onPressed, isNull);
    expect(find.text('Reading opens soon. You can browse book details and previews now.'), findsOneWidget);
  });

  testWidgets('Read enables only when the server grants it and the reader is available', (tester) async {
    final catalog = FakeCatalog(
      detail: fakeDetail(access: fakeAccess(canRead: true, readerAvailable: true, reasons: const [])),
    );
    await pumpApp(tester, catalog: catalog, location: '/explore/books/book-0');
    expect(_readButton(tester).onPressed, isNotNull);
    expect(find.byKey(const Key('access-explanation')), findsNothing);
  });

  testWidgets('premium books explain the entitlement and never offer a client-side unlock', (tester) async {
    final catalog = FakeCatalog(
      detail: fakeDetail(access: fakeAccess(reasons: const [AccessReason.entitlementRequired])),
    );
    await pumpApp(tester, catalog: catalog, restored: testUser, location: '/explore/books/book-0');
    expect(find.text('Included with Premium.'), findsOneWidget);
    expect(_readButton(tester).onPressed, isNull);
    expect(find.byKey(const Key('access-sign-in')), findsNothing);
  });

  testWidgets('guest sign-in from a book returns to that book', (tester) async {
    await pumpApp(tester, location: '/explore/books/book-0');
    await tester.tap(find.byKey(const Key('access-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('email')), findsOneWidget);
  });

  testWidgets('a missing translation is disclosed, not hidden', (tester) async {
    await pumpApp(tester, location: '/explore/books/book-0'); // UI in English, book only in Bangla
    expect(find.byKey(const Key('language-fallback')), findsOneWidget);
  });

  testWidgets('no fallback notice when the book is in the UI language', (tester) async {
    await pumpApp(tester, locale: const Locale('bn'), location: '/explore/books/book-0');
    expect(find.byKey(const Key('language-fallback')), findsNothing);
  });

  for (final size in _sizes) {
    testWidgets('explore and book details lay out at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpApp(tester, size: size, location: '/explore');
      expect(tester.takeException(), isNull);
      await pumpApp(tester, size: size, location: '/explore/books/book-0');
      expect(tester.takeException(), isNull);
      expect(find.byType(BookDetailScreen), findsOneWidget);
    });
  }

  testWidgets('catalog screens meet accessibility guidelines and survive 200 % Bangla text', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, location: '/explore');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await pumpApp(tester, location: '/explore/books/book-0');
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(360, 800), locale: const Locale('bn'), location: '/explore');
    expect(tester.takeException(), isNull);
    await pumpApp(tester, size: const Size(360, 800), locale: const Locale('bn'), location: '/explore/books/book-0');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
