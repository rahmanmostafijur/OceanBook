import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oceanbook_mobile/features/library/domain/library_book.dart';
import 'package:oceanbook_mobile/features/library/presentation/widgets/category_pills.dart';
import 'package:oceanbook_mobile/features/library/presentation/widgets/library_book_card.dart';
import 'package:oceanbook_mobile/features/reader/presentation/reader_settings_controller.dart';
import 'package:reader_core/reader_core.dart';

import 'support/harness.dart';

const _novel = 'নন্দিত নরকে';
const _science = 'কসমস';

/// The card for a title (the cover placeholder repeats the title, so plain text finders match twice).
Finder card(String title) => find.byWidgetPredicate((w) => w is LibraryBookCard && w.book.title == title);

void main() {
  group('LibraryBook', () {
    test('matches title or author, ignoring case and surrounding space', () {
      const book = LibraryBook(
        id: 'b',
        title: 'Cosmos',
        author: 'Carl Sagan',
        category: 'Science',
        synopsis: '',
      );
      expect(book.matches(''), isTrue);
      expect(book.matches('  cos '), isTrue);
      expect(book.matches('SAGAN'), isTrue);
      expect(book.matches('novel'), isFalse);
    });

    test('progress outside 0-100 is rejected', () {
      expect(
        () => LibraryBook(id: 'b', title: 't', author: 'a', category: 'c', synopsis: '', progressPercent: 101),
        throwsAssertionError,
      );
    });
  });

  group('library dashboard', () {
    testWidgets('shows the grid with progress, filters by search and category', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      expect(card(_novel), findsOneWidget);
      expect(find.text('64% read'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);

      await tester.enterText(find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)), 'কসমস');
      await tester.pumpAndSettle();
      expect(card(_science), findsOneWidget);
      expect(card(_novel), findsNothing);

      await tester.enterText(
        find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)),
        'zzz-no-match',
      );
      await tester.pumpAndSettle();
      expect(find.text('No books match your search'), findsOneWidget);

      await tester.enterText(find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)), '');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'বিজ্ঞান'),
        100,
        scrollable: find.descendant(of: find.byType(CategoryPills), matching: find.byType(Scrollable)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'বিজ্ঞান'));
      await tester.pumpAndSettle();
      expect(card(_science), findsOneWidget);
      expect(card(_novel), findsNothing);

      await tester.drag(find.byType(CategoryPills), const Offset(600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(card(_novel), findsOneWidget);
    });

    testWidgets('lays out two columns on a phone and more on a tablet', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      final phoneTile = tester.getSize(find.byType(LibraryBookCard).at(0));
      expect(phoneTile.width, lessThan(200));

      await pumpApp(tester, restored: testUser, location: '/library', size: const Size(1100, 800));
      final tabletTile = tester.getSize(find.byType(LibraryBookCard).at(0));
      expect(tabletTile.width, lessThan(phoneTile.width + 60));
      final firstRowTops = {
        for (var i = 0; i < 6; i++) tester.getTopLeft(find.byType(LibraryBookCard).at(i)).dy,
      };
      expect(firstRowTops.length, lessThan(3), reason: 'six tiles fit in at most two rows on a wide screen');
    });

    testWidgets('has no overflow at 200 % text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, restored: testUser, location: '/library');
      expect(tester.takeException(), isNull);
      expect(card(_novel), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });

  group('book details sheet', () {
    testWidgets('shows details, toggles the synopsis and offers Continue for a started book', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await tester.tap(card(_novel));
      await tester.pumpAndSettle();

      expect(find.text('Synopsis'), findsOneWidget);
      expect(find.bySemanticsLabel('Rated 4.5 out of 5'), findsOneWidget);
      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('Read more'), findsOneWidget);

      await tester.ensureVisible(find.text('Read more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read more'));
      await tester.pumpAndSettle();
      expect(find.text('Read less'), findsOneWidget);
      await tester.ensureVisible(find.text('Read less'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read less'));
      await tester.pumpAndSettle();
      expect(find.text('Read more'), findsOneWidget);
    });

    testWidgets('a book not started yet says Start reading', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await tester.enterText(
        find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)),
        'পথের পাঁচালী',
      );
      await tester.pumpAndSettle();
      await tester.tap(card('পথের পাঁচালী'));
      await tester.pumpAndSettle();
      expect(find.text('Start reading'), findsOneWidget);
    });

    testWidgets('the call to action opens the reader', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await tester.tap(card(_novel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue reading'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reading settings'), findsOneWidget);
      expect(find.byTooltip('Close reader'), findsOneWidget);
    });
  });

  group('reader', () {
    Future<void> openReader(WidgetTester tester) async {
      await pumpApp(tester, restored: testUser, location: '/library/read/lib-01');
    }

    ReaderSettings currentSettings(WidgetTester tester) {
      final element = tester.element(find.byTooltip('Reading settings'));
      return ProviderScope.containerOf(element).read(readerSettingsProvider);
    }

    testWidgets('reading progress is labelled for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await openReader(tester);
      expect(find.bySemanticsLabel('Reading progress'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('settings change size, theme and alignment live', (tester) async {
      await openReader(tester);
      expect(currentSettings(tester).fontScale, 1.0);

      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byTooltip('Larger text'));
      await tester.pumpAndSettle();
      expect(find.text('110%'), findsOneWidget);
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.tap(find.byTooltip('Smaller text'));
      await tester.pumpAndSettle();
      expect(find.text('90%'), findsOneWidget);

      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();
      expect(currentSettings(tester).theme, ReaderTheme.dark);
      await tester.tap(find.text('Sepia'));
      await tester.pumpAndSettle();
      expect(currentSettings(tester).theme, ReaderTheme.sepia);
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(currentSettings(tester).theme, ReaderTheme.light);

      await tester.tap(find.text('Justified'));
      await tester.pumpAndSettle();
      expect(currentSettings(tester).justify, isTrue);
      await tester.tap(find.text('Left'));
      await tester.pumpAndSettle();
      expect(currentSettings(tester).justify, isFalse);
    });

    testWidgets('text size stops at the limits', (tester) async {
      await openReader(tester);
      await tester.tap(find.byTooltip('Reading settings'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        final button = find.widgetWithIcon(IconButton, Icons.text_decrease);
        if (tester.widget<IconButton>(button).onPressed == null) break;
        await tester.tap(button);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('80%'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.text_decrease)).onPressed, isNull);
    });

    testWidgets('tapping the page hides and shows the controls; close returns to the library', (tester) async {
      await openReader(tester);
      double chrome() => tester
          .widget<FadeTransition>(
            find.ancestor(of: find.byTooltip('Close reader'), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value;
      expect(chrome(), 1);

      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(chrome(), 0);
      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(chrome(), 1);

      await tester.tap(find.byTooltip('Close reader'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsOneWidget);
    });

    testWidgets('guests cannot open the reader', (tester) async {
      await pumpApp(tester, location: '/library/read/lib-01');
      expect(find.text('Welcome to OceanBook'), findsOneWidget);
    });

    testWidgets('Bangla labels render', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library/read/lib-01', locale: const Locale('bn'));
      await tester.tap(find.byTooltip('পড়ার সেটিংস'));
      await tester.pumpAndSettle();
      expect(find.text('লেখার আকার'), findsOneWidget);
      expect(find.text('সেপিয়া'), findsOneWidget);
    });
  });
}
