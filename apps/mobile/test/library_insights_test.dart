import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ob_core/ob_core.dart';
import 'package:oceanbook_mobile/core/settings/app_settings.dart';
import 'package:oceanbook_mobile/features/library/data/library_providers.dart';
import 'package:oceanbook_mobile/features/library/domain/library_insights.dart';

import 'support/fake_library.dart';

LibraryItem finished(String id, int daysAgo, {int? pages}) => libraryItem(
  id,
  id,
  status: ShelfStatus.finished,
  finishedDaysAgo: daysAgo,
  addedDaysAgo: daysAgo + 1,
  pages: pages,
);

void main() {
  group('LibraryInsights', () {
    test('counts statuses, favourites and the share finished', () {
      final insights = LibraryInsights.compute(sampleLibrary(), now: testNow);
      expect(insights.total, 5);
      expect(insights.countOf(ShelfStatus.reading), 1);
      expect(insights.countOf(ShelfStatus.wantToRead), 2);
      expect(insights.countOf(ShelfStatus.finished), 2);
      expect(insights.favorites, 1);
      expect(insights.finishedPercent, 40);
      expect(insights.year, 2026);
    });

    test('pages count only finished books with a known page count, and say how many are unknown', () {
      final insights = LibraryInsights.compute([
        finished('a', 1, pages: 100),
        finished('b', 2),
        libraryItem('c', 'c', status: ShelfStatus.reading, pages: 500),
      ], now: testNow);
      expect(insights.pagesFinished, 100);
      expect(insights.finishedWithoutPageCount, 1);
    });

    test('finished this year uses the device calendar year', () {
      final insights = LibraryInsights.compute([
        finished('this-year', 2),
        finished('last-year', 400),
      ], now: testNow);
      expect(insights.finishedThisYear, 1);
    });

    test('week has seven daily buckets ending today', () {
      final insights = LibraryInsights.compute([
        finished('today', 0),
        finished('six', 6),
        finished('seven', 7),
      ], now: testNow);
      final week = insights.finishedSeries(InsightPeriod.week);
      expect(week, hasLength(7));
      expect(week.last.start, DateTime(2026, 10, 26));
      expect(week.first.start, DateTime(2026, 10, 20));
      expect(week.last.count, 1);
      expect(week.first.count, 1);
      expect(insights.finishedIn(InsightPeriod.week), 2, reason: 'seven days ago is outside the week');
    });

    test('month covers the last 30 days in five buckets', () {
      final insights = LibraryInsights.compute([finished('a', 29), finished('b', 30), finished('c', 0)], now: testNow);
      final month = insights.finishedSeries(InsightPeriod.month);
      expect(month, hasLength(5));
      expect(month.first.start, DateTime(2026, 9, 27));
      expect(insights.finishedIn(InsightPeriod.month), 2);
    });

    test('year has twelve calendar months ending with the current one', () {
      final insights = LibraryInsights.compute([
        finished('a', 0),
        finished('b', 330),
        finished('c', 400),
      ], now: testNow);
      final year = insights.finishedSeries(InsightPeriod.year);
      expect(year, hasLength(12));
      expect(year.first.start, DateTime(2025, 11));
      expect(year.last.start, DateTime(2026, 10));
      expect(year.first.count, 1);
      expect(insights.finishedIn(InsightPeriod.year), 2);
    });

    test('lifetime groups by year and folds anything older than ten years into the first bar', () {
      final insights = LibraryInsights.compute([
        finished('recent', 10),
        finished('old', 365 * 15),
      ], now: testNow);
      final lifetime = insights.finishedSeries(InsightPeriod.lifetime);
      expect(lifetime, hasLength(10));
      expect(lifetime.first.start.year, 2017);
      expect(lifetime.first.includesEarlier, isTrue);
      expect(lifetime.first.count, 1);
      expect(insights.finishedIn(InsightPeriod.lifetime), 2);
    });

    test('lifetime of an empty history is the current year only', () {
      final lifetime = LibraryInsights.compute([
        libraryItem('a', 'a'),
      ], now: testNow).finishedSeries(InsightPeriod.lifetime);
      expect(lifetime.single.start.year, 2026);
      expect(lifetime.single.count, 0);
    });

    test('rankings keep the top five and sum the rest as other', () {
      final items = [
        for (var i = 0; i < 8; i++)
          libraryItem(
            'b$i',
            'b$i',
            category: NamedRef(id: 'c$i', slug: 'c$i', name: 'Cat $i'),
          ),
        libraryItem(
          'x',
          'x',
          category: const NamedRef(id: 'c0', slug: 'c0', name: 'Cat 0'),
        ),
        libraryItem('y', 'y', category: null),
      ];
      final ranking = LibraryInsights.compute(items, now: testNow).categories;
      expect(ranking.top, hasLength(insightTopCount));
      expect(ranking.top.first.label, 'Cat 0');
      expect(ranking.top.first.count, 2);
      expect(ranking.otherCount, 3);
    });

    test('longest, shortest and top rated use only books that have the data', () {
      final items = [
        libraryItem('short', 'short', pages: 50),
        libraryItem('long', 'long', pages: 900),
        libraryItem('none', 'none'),
        libraryItem('rated-many', 'rated-many', rating: 4.5, ratingCount: 40),
        libraryItem('rated-few', 'rated-few', rating: 4.5, ratingCount: 2),
        libraryItem('best', 'best', rating: 4.9, ratingCount: 1),
      ];
      final insights = LibraryInsights.compute(items, now: testNow);
      expect(insights.longest.map((b) => b.bookId), ['long', 'short']);
      expect(insights.shortest.first.bookId, 'short');
      expect(insights.booksWithPageCount, 2);
      expect(insights.topRated.map((b) => b.bookId), ['best', 'rated-many', 'rated-few']);
    });

    test('books added per month covers twelve months', () {
      final added = LibraryInsights.compute(sampleLibrary(), now: testNow).addedPerMonth;
      expect(added, hasLength(12));
      expect(added.fold(0, (sum, b) => sum + b.count), 5);
    });
  });

  group('LibraryView', () {
    test('filters by status and favourite, then searches', () {
      final books = sampleLibrary();
      expect(const LibraryView(filter: LibraryShelfFilter.finished).apply(books), hasLength(2));
      expect(const LibraryView(filter: LibraryShelfFilter.favorites).apply(books).single.bookId, 'lib-01');
      expect(const LibraryView(query: 'হুমায়ূন').apply(books), hasLength(5));
      expect(const LibraryView(query: 'কসমস').apply(books).single.bookId, 'lib-02');
    });

    test('sorts without changing the input list', () {
      final books = sampleLibrary();
      final order = books.map((b) => b.bookId).toList();
      final byTitle = const LibraryView(sort: LibrarySort.title).apply(books);
      expect(byTitle.first.title, 'A Brief History');
      expect(books.map((b) => b.bookId), order);
      expect(const LibraryView().apply(books).first.bookId, 'lib-01', reason: 'most recently added first');
    });
  });

  group('device preferences', () {
    test('language and theme survive a restart', () {
      final store = MemoryPreferenceStore();
      final first = ProviderContainer(overrides: [preferenceStoreProvider.overrideWithValue(store)]);
      first.read(themeModeProvider.notifier).set(ThemeMode.dark);
      first.read(localeProvider.notifier).set(const Locale('en'));
      first.dispose();

      final second = ProviderContainer(overrides: [preferenceStoreProvider.overrideWithValue(store)]);
      addTearDown(second.dispose);
      expect(second.read(themeModeProvider), ThemeMode.dark);
      expect(second.read(localeProvider), const Locale('en'));
    });

    test('defaults are Bangla and the system theme; unknown stored values are ignored', () async {
      final store = MemoryPreferenceStore();
      await store.write('ui.locale', 'fr');
      await store.write('ui.theme_mode', 'neon');
      final container = ProviderContainer(overrides: [preferenceStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);
      expect(container.read(localeProvider), const Locale('bn'));
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });
}
