import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_mobile/features/books/presentation/book_detail_screen.dart';
import 'package:oceanbook_mobile/features/library/data/library_providers.dart';
import 'package:oceanbook_mobile/features/library/presentation/widgets/book_details_sheet.dart';
import 'package:oceanbook_mobile/features/library/presentation/widgets/filter_pills.dart';
import 'package:oceanbook_mobile/features/library/presentation/widgets/library_book_card.dart';
import 'package:oceanbook_mobile/features/reader/presentation/reader_settings_controller.dart';
import 'package:reader_core/reader_core.dart';

import 'support/harness.dart';

const _novel = 'নন্দিত নরকে';
const _science = 'কসমস';
const _unread = 'পথের পাঁচালী';

/// The card for a title (the cover placeholder repeats the title, so plain text finders match twice).
Finder card(String title) => find.byWidgetPredicate((w) => w is LibraryBookCard && w.book.title == title);

Finder chip(String label) => find.widgetWithText(ChoiceChip, label);

/// Taps a status filter, scrolling the chip row to it first (backwards with a negative [delta]).
Future<void> selectFilter(WidgetTester tester, String label, {double delta = 100}) async {
  await tester.scrollUntilVisible(
    chip(label),
    delta,
    scrollable: find.descendant(of: find.byType(FilterPills<LibraryShelfFilter>), matching: find.byType(Scrollable)),
  );
  await tester.ensureVisible(chip(label));
  await tester.pumpAndSettle();
  await tester.tap(chip(label));
  await tester.pumpAndSettle();
}

/// Taps something in the details sheet, scrolling its lazily built list to it first.
Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.descendant(of: find.byType(BookDetailsSheet), matching: find.byType(Scrollable)).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Dismisses a modal sheet by tapping the barrier above it.
Future<void> closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.widgetWithText(Tab, tab));
  await tester.pumpAndSettle();
}

Future<void> openSheet(WidgetTester tester, String title) async {
  await tester.tap(card(title));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

BookCollection shelf(String id, String name, List<String> ids) => BookCollection(
  id: id,
  name: name,
  position: 0,
  bookIds: ids,
  createdAt: testNow,
  updatedAt: testNow,
);

void main() {
  group('library books', () {
    testWidgets('lists the books with their status and filters by status, favourite and search', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      expect(card(_novel), findsOneWidget);
      expect(card(_science), findsOneWidget);
      expect(find.text('5 books'), findsOneWidget);

      await selectFilter(tester, 'Finished (2)');
      expect(card(_science), findsOneWidget);
      expect(card('A Brief History'), findsOneWidget);
      expect(card(_novel), findsNothing);

      await selectFilter(tester, 'Favourites (1)');
      expect(card(_novel), findsOneWidget);
      expect(card(_science), findsNothing);

      await selectFilter(tester, 'All (5)', delta: -100);
      await tester.enterText(find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)), 'কসমস');
      await tester.pumpAndSettle();
      expect(card(_science), findsOneWidget);
      expect(card(_novel), findsNothing);

      await tester.enterText(find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No books match your search'), findsOneWidget);
    });

    testWidgets('search text survives switching tabs', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await tester.enterText(find.descendant(of: find.byType(SearchBar), matching: find.byType(TextField)), 'কসমস');
      await tester.pumpAndSettle();
      await openTab(tester, 'Insights');
      await openTab(tester, 'Books');
      expect(find.descendant(of: find.byType(SearchBar), matching: find.text('কসমস')), findsOneWidget);
      expect(card(_novel), findsNothing);
    });

    testWidgets('sorts by title', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await tester.tap(find.byTooltip('Sort books'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<LibrarySort>, 'Title'));
      await tester.pumpAndSettle();
      final first = tester.getTopLeft(card('A Brief History'));
      expect(first.dy, lessThanOrEqualTo(tester.getTopLeft(card(_novel)).dy));
      expect(first.dx, lessThan(tester.getTopLeft(card(_novel)).dx + 1));
    });

    testWidgets('an empty library invites the user to explore', (tester) async {
      await pumpApp(
        tester,
        restored: testUser,
        location: '/library',
        library: FakeLibrary(items: []),
      );
      expect(find.text('Your library is empty'), findsOneWidget);
      await tester.tap(find.text('Explore books'));
      await tester.pumpAndSettle();
      expect(find.text('Your library is empty'), findsNothing);
    });

    testWidgets('lays out two columns on a phone and more on a tablet', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      final phoneTile = tester.getSize(find.byType(LibraryBookCard).at(0));
      expect(phoneTile.width, lessThan(200));

      await pumpApp(tester, restored: testUser, location: '/library', size: const Size(1100, 800));
      final tabletTile = tester.getSize(find.byType(LibraryBookCard).at(0));
      expect(tabletTile.width, lessThan(phoneTile.width + 60));
      final firstRowTops = {
        for (var i = 0; i < 5; i++) tester.getTopLeft(find.byType(LibraryBookCard).at(i)).dy,
      };
      expect(firstRowTops.length, 1, reason: 'five tiles fit in one row on a wide screen');
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
    testWidgets('changes the status and favourite through the server', (tester) async {
      final library = FakeLibrary();
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openSheet(tester, _unread);
      await tapInSheet(tester, chip('Reading'));
      expect(library.calls, contains('save:lib-03:reading:null'));
      expect(find.textContaining('Started'), findsOneWidget);

      await tapInSheet(tester, find.byKey(const Key('library-favorite')));
      expect(library.calls, contains('save:lib-03:null:true'));
      expect(find.text('Remove from favourites'), findsOneWidget);

      await closeSheet(tester);
      expect(chip('Reading (2)'), findsOneWidget);
      await selectFilter(tester, 'Favourites (2)');
      expect(card(_unread), findsOneWidget);
    });

    testWidgets('a failed change is reported and nothing changes', (tester) async {
      final library = FakeLibrary()
        ..failNext = const ServerFailure(
          status: 500,
          errors: [ApiErrorItem(code: ApiErrorCode.internalError, message: 'x')],
        );
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openSheet(tester, _unread);
      await tapInSheet(tester, chip('Finished'));
      expect(find.text("We're having trouble right now. Please try again shortly."), findsOneWidget);
      expect(tester.widget<ChoiceChip>(chip('Want to read')).selected, isTrue);
    });

    testWidgets('removing asks first; cancelling keeps the book', (tester) async {
      final library = FakeLibrary(
        shelves: [
          shelf('s1', 'Weekend', ['lib-01']),
        ],
      );
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openSheet(tester, _novel);
      await tapInSheet(tester, find.byKey(const Key('library-remove')));
      expect(find.text('Remove this book?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.calls.where((c) => c.startsWith('remove')), isEmpty);

      await tapInSheet(tester, find.byKey(const Key('library-remove')));
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(library.calls, contains('remove:lib-01'));
      expect(card(_novel), findsNothing);
      expect(find.text('Removed from your library'), findsOneWidget);

      await openTab(tester, 'Shelves');
      expect(find.text('No books'), findsOneWidget, reason: 'the book left its shelf too');
    });

    testWidgets('offers the book page', (tester) async {
      await pumpApp(tester, restored: testUser, location: '/library');
      await openSheet(tester, _novel);
      await tester.tap(find.text('View book page'));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailScreen), findsOneWidget);
    });
  });

  group('shelves', () {
    testWidgets('create a shelf, add a book from the picker and see it on the shelf', (tester) async {
      final library = FakeLibrary();
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openTab(tester, 'Shelves');
      expect(find.text('Organise your books into shelves'), findsOneWidget);

      await tester.tap(find.text('New shelf'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Shelf name'), 'Weekend');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(library.calls, contains('create:Weekend'));

      await tester.tap(find.text('Weekend'));
      await tester.pumpAndSettle();
      expect(find.text('This shelf is empty'), findsOneWidget);
      await tester.tap(find.text('Add books'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, _science).first);
      await tester.pumpAndSettle();
      expect(library.calls.last, startsWith('add:'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('1 book'), findsOneWidget);
      expect(find.text(_science), findsWidgets);

      await tester.tap(find.byTooltip('Remove from shelf'));
      await tester.pumpAndSettle();
      expect(find.text('This shelf is empty'), findsOneWidget);
    });

    testWidgets('a duplicate name shows the server message in the form', (tester) async {
      await pumpApp(
        tester,
        restored: testUser,
        location: '/library',
        library: FakeLibrary(shelves: [shelf('s1', 'Weekend', const [])]),
      );
      await openTab(tester, 'Shelves');
      await tester.tap(find.text('New shelf'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Shelf name'), 'weekend');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('You already have a shelf with this name.'), findsOneWidget);
    });

    testWidgets('deleting a shelf asks first and keeps its books in the library', (tester) async {
      final library = FakeLibrary(
        shelves: [
          shelf('s1', 'Weekend', ['lib-01', 'lib-02']),
        ],
      );
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openTab(tester, 'Shelves');
      expect(find.text('2 books'), findsOneWidget);
      await tester.tap(find.byTooltip('Options for Weekend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete shelf'));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Weekend”?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(library.calls, contains('delete:s1'));
      expect(find.text('Organise your books into shelves'), findsOneWidget);
      await openTab(tester, 'Books');
      expect(card(_novel), findsOneWidget);
    });

    testWidgets('the details sheet puts a book on a shelf', (tester) async {
      final library = FakeLibrary(shelves: [shelf('s1', 'Weekend', const [])]);
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openSheet(tester, _novel);
      await tapInSheet(tester, find.widgetWithText(FilterChip, 'Weekend'));
      expect(library.calls, contains('add:s1:lib-01'));
      expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Weekend')).selected, isTrue);
    });
  });

  group('insights', () {
    testWidgets('figures come from the library and the period picker changes the chart', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, restored: testUser, location: '/library');
      await openTab(tester, 'Insights');
      expect(find.bySemanticsLabel('Books, 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Finished in 2026, 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Reading now, 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Pages finished, 608'), findsOneWidget);
      expect(find.text('2 books in this period'), findsOneWidget);

      await tester.tap(chip('Week'));
      await tester.pumpAndSettle();
      expect(find.text('1 book in this period'), findsOneWidget);
      await tester.tap(chip('All time'));
      await tester.pumpAndSettle();
      expect(find.text('2 books in this period'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Top categories'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('উপন্যাস'), findsOneWidget);
      expect(find.text('বিজ্ঞান'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a week without finished books says so instead of an empty chart', (tester) async {
      final library = FakeLibrary(items: [libraryItem('x', 'Old', status: ShelfStatus.finished, finishedDaysAgo: 40)]);
      await pumpApp(tester, restored: testUser, location: '/library', library: library);
      await openTab(tester, 'Insights');
      await tester.tap(chip('Week'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing finished in this period'), findsOneWidget);
    });

    testWidgets('an empty library explains where insights come from', (tester) async {
      await pumpApp(
        tester,
        restored: testUser,
        location: '/library',
        library: FakeLibrary(items: []),
      );
      await openTab(tester, 'Insights');
      expect(find.text('Insights appear as your library grows'), findsOneWidget);
    });

    for (final size in [const Size(320, 640), const Size(1280, 900)]) {
      testWidgets('insights have no overflow at 200 % text on ${size.width.toInt()} dp', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(tester, restored: testUser, location: '/library', size: size);
        await openTab(tester, 'Insights');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('book page library actions', () {
    testWidgets('guests are asked to sign in', (tester) async {
      await pumpApp(tester, location: '/explore/books/book-0');
      await tester.ensureVisible(find.byKey(const Key('library-add')));
      await tester.tap(find.byKey(const Key('library-add')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to OceanBook'), findsOneWidget);
    });

    testWidgets('signed-in users add the book, then change status and favourite', (tester) async {
      final library = FakeLibrary(items: []);
      await pumpApp(tester, restored: testUser, location: '/explore/books/book-0', library: library);
      await tapVisible(tester, find.byKey(const Key('library-add')));
      expect(library.calls, ['save:book-0:null:null']);
      expect(find.text('Added to your library'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('library-status')));
      await tester.tap(find.widgetWithText(MenuItemButton, 'Finished'));
      await tester.pumpAndSettle();
      expect(library.calls.last, 'save:book-0:finished:null');

      await tapVisible(tester, find.byKey(const Key('library-favorite')));
      expect(library.calls.last, 'save:book-0:null:true');
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

    testWidgets('controls stay shown for screen-reader users even after tapping the page', (tester) async {
      await openReader(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
        accessibleNavigation: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpAndSettle();
      double chrome() => tester
          .widget<FadeTransition>(
            find.ancestor(of: find.byTooltip('Close reader'), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value;
      expect(chrome(), 1);

      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(chrome(), 1);
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
