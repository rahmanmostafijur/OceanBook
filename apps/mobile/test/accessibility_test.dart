import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:ob_l10n/ob_l10n.dart';
import 'package:oceanbook_mobile/app.dart';
import 'package:oceanbook_mobile/core/router/app_router.dart';
import 'package:oceanbook_mobile/features/library/presentation/widgets/library_book_card.dart';

import 'support/harness.dart';

// The test font draws every glyph as a full-em square, so strings are kept short enough to need at most
// the allowed lines at 300 % scale.
const _tileWidth = 200.0;

/// A catalog whose book lookup never completes, so the detail page stays in its loading state.
class _PendingCatalog extends FakeCatalog {
  @override
  Future<BookDetail> book(String idOrSlug) => Completer<BookDetail>().future;
}

Future<void> _pumpCard(WidgetTester tester, Locale locale, LibraryItem book, double scale) async {
  tester.view.physicalSize = const Size(600, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: ObLocalizations.localizationsDelegates,
      supportedLocales: ObLocalizations.supportedLocales,
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _tileWidth,
              height: _tileWidth / AppSizes.coverAspectRatio + libraryCardTextHeight(context),
              child: LibraryBookCard(book: book, onTap: () {}),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final english = libraryItem(
    'e',
    'Cosmos Sea',
    status: ShelfStatus.reading,
    favorite: true,
    contributors: const [Contributor(id: 'a', slug: 'sagan', name: 'Carl Sagan', role: 'author')],
  );
  final bangla = libraryItem(
    'b',
    'কসমস',
    status: ShelfStatus.finished,
    contributors: const [Contributor(id: 'a', slug: 'ahmed', name: 'আহমেদ', role: 'author')],
  );

  for (final (name, locale, book) in [
    ('English', const Locale('en'), english),
    ('Bangla', const Locale('bn'), bangla),
  ]) {
    for (final scale in [2.0, 3.0]) {
      testWidgets('library card shows full $name text without overflow at ${scale * 100} % text', (tester) async {
        await _pumpCard(tester, locale, book, scale);
        expect(tester.takeException(), isNull);
        for (final text in [book.title, book.authorNames.single]) {
          // The cover placeholder repeats the title first; the card's own text is the last match.
          final paragraph = tester.renderObject<RenderParagraph>(find.text(text).last);
          expect(paragraph.didExceedMaxLines, isFalse, reason: '$text truncated');
        }
      });
    }
  }

  for (final locale in [const Locale('en'), const Locale('bn')]) {
    testWidgets('library grid has no overflow at 300 % text in ${locale.languageCode}', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester, locale: locale, restored: testUser, location: '/library');
      expect(tester.takeException(), isNull);
      expect(find.byType(LibraryBookCard), findsWidgets);
    });
  }

  testWidgets('a representative page shows the shared labelled loading widget', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, catalog: _PendingCatalog());
    ProviderScope.containerOf(tester.element(find.byType(OceanBookApp))).read(routerProvider).go('/explore/books/x');
    await tester.pump();
    await tester.pump();
    expect(find.byType(PageLoading), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Loading'));
    expect(node.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
